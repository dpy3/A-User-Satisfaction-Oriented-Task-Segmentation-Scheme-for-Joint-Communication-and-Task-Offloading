function Validate_Strict_V2()
root=fileparts(mfilename('fullpath')); cfg=MCA_Official_Setup('baselineformal');
out=struct('BudgetBoundaryChecks',0,'DisabledLocalChecks',0,'MonotonePolishChecks',0);
for N=[120,300]
    rng(20261015+N,'twister'); [Task,Fog,Thing,DNN,Pre]=generate_tier1_env_trace(N,5);
    for budget=[100,101,137,250,501]
        for enabled=[false,true]
            p=struct('lr',0.1,'rho',0.01,'mu',1.05,'alpha',0.8,'pop_size',100, ...
                'deadline_scale',0.85,'max_gen',10,'local_search_prob',1, ...
                'alm_steps_per_gen',5,'guarded_local_search',true,'repair_aware_fitness',true, ...
                'local_search_enabled',enabled,'score_budget',budget,'enable_internal_global_opt',false);
            rng(1001,'twister'); MCA_Audit_Count('reset');
            [raw,~,~,diag]=M_CA_ALM_Solver(Task,Fog,Thing,DNN,50,[],[],p,false,Pre);
            c=MCA_Audit_Count('get');
            assert(c.ScoreCalls==budget && diag.score_calls==budget,'Audit:BoundaryCalls');
            if ~enabled, assert(c.LocalInvocations==0 && c.InnerUpdates==0); out.DisabledLocalChecks=out.DisabledLocalChecks+1; end
            theta=Perform_Safe_Harbor_Repair(raw,Pre,Fog,Task,DNN);
            [s,~,b]=calculate_metrics_v2(theta,Task,Fog,[],DNN,Pre,true);
            assert(b.resource_viol_rate==0);
            if budget==137
                before=rng;
                [polished,d]=MCA_Polish_Monotone(theta,Pre,Fog,Task,DNN,1);
                assert(isequal(before,rng),'Audit:PolishRNG');
                [s2,~,b2]=calculate_metrics_v2(polished,Task,Fog,[],DNN,Pre,true);
                assert(s2+1e-12>=s && b2.resource_viol_rate==0 && all(sum(polished>0,2)<=1));
                out.MonotonePolishChecks=out.MonotonePolishChecks+1;
            end
            out.BudgetBoundaryChecks=out.BudgetBoundaryChecks+1;
        end
    end
end
out.Passed=true; out.Scope='Diagnostic boundary and invariant checks, not formal performance evidence.';
fid=fopen(fullfile(fileparts(root),'STRICT_V2_VALIDATION.json'),'w');
fprintf(fid,'%s',jsonencode(out,PrettyPrint=true));fclose(fid);disp(out);
Run_Strict_V2(901,[120,300],501,'diagnostic');
end
