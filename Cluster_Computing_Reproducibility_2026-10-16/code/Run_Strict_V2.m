function Run_Strict_V2(run_indices, scales, score_budget, stage)
% Four same-engine arms: ranking raw/repair x local updates on/off.
% A repair-only output makes repair-aware selection exactly match delivery.
if nargin<1, run_indices=1:30; end
if nargin<2, scales=[120,150,180,200,250,300]; end
if nargin<3, score_budget=10000; end
if nargin<4, stage='formal'; end
root=fileparts(mfilename('fullpath')); cfg=MCA_Official_Setup('baselineformal');
cfg.schema_version='MCA-STRICT-V2-REPAIR-ONLY';
cfg.enable_post_opt=false; cfg.score_budget=score_budget;
cfg.local_probability=0.25; cfg.inner_updates=5;
cfg.test_run_indices=run_indices; cfg.test_scales=scales;
cfg.results_root=fullfile(root,'Results',['STRICT_V2_' upper(stage)], ...
    sprintf('R%dto%d',run_indices(1),run_indices(end)));
if ~exist(cfg.results_root,'dir'), mkdir(cfg.results_root); end
MCA_Write_Manifest(cfg,{mfilename('fullpath')});
path_csv=fullfile(cfg.results_root,'Strict_RunLevel.csv');
rows=repmat(row_template(),0,1);
checkpoint=fullfile(cfg.results_root,'Strict_Checkpoint.mat');
if exist(checkpoint,'file'), saved=load(checkpoint,'rows'); rows=saved.rows; end
arms={'RawLocalOff','RawLocalOn','RepairLocalOff','RepairLocalOn'};
for N=scales
    for run=run_indices
        env_seed=cfg.seed_base+100000*find(cfg.seed_scale_reference==N,1)+run;
        assert(~isempty(env_seed),'MCA:MissingScaleSeed');
        rng(env_seed,'twister'); [Task,Fog,Thing,DNN_Data,Pre]=generate_tier1_env_trace(N,5);
        Pre.Mean_Deadline=mean(Task(:,3)); Pre.Violation_Mode='composite';
        for arm=1:4
            name=arms{arm};
            if any([rows.N]==N & [rows.Run]==run & strcmp({rows.Algorithm},name)), continue; end
            params=parameters(N,score_budget,contains(name,'Repair'),contains(name,'On'));
            % Same solver seed, including invocation draws in the disabled arm.
            % Different budget allocation can produce different generation counts.
            solver_seed=env_seed+3000; rng(solver_seed,'twister');
            MCA_Audit_Count('reset'); timer=tic;
            [raw,~,~,diag]=M_CA_ALM_Solver(Task,Fog,Thing,DNN_Data,50,[],[],params,false,Pre);
            theta=Perform_Safe_Harbor_Repair(raw,Pre,Fog,Task,DNN_Data);
            solver_repair_seconds=toc(timer);
            timer=tic;
            m=MCA_Evaluate(theta,Task,Fog,Thing,DNN_Data,Pre,name);
            report_seconds=toc(timer);
            counts=MCA_Audit_Count('get');
            assert(counts.ScoreCalls==score_budget && diag.score_calls==score_budget,'MCA:WrongCalls');
            assert(m.ResourceViolation==0,'MCA:ResourceViolation');
            row=row_template(); row.SchemaVersion=cfg.schema_version;
            row.EvidenceClass=stage; row.N=N; row.Run=run; row.EnvironmentSeed=env_seed;
            row.SolverSeed=solver_seed; row.Algorithm=name; row.CandidateScoreBudget=score_budget;
            row.Sat=m.Sat; row.Admission=m.Admission; row.ResourceViolation=m.ResourceViolation;
            row.SatisfiedCount=m.SatisfiedCount; row.AdmittedCount=m.AdmittedCount; row.TaskCount=N;
            row.RejectedCount=sum(sum(theta>0,2)==0);
            row.MultiAssignedCount=sum(sum(theta>0,2)>1);
            row.SolverAndRepairSec=solver_repair_seconds;
            row.ReportingSec=report_seconds; row.EndToEndSec=solver_repair_seconds+report_seconds;
            fields=fieldnames(counts);
            for f=1:numel(fields), row.(fields{f})=counts.(fields{f}); end
            row.ChangedLocalGenes=diag.changed_local_genes;
            rows(end+1)=row; %#ok<AGROW>
            save(checkpoint,'rows','cfg'); writetable(struct2table(rows),path_csv);
            fprintf('STRICT %s N=%d R=%d %s Sat=%.2f calls=%d local=%d time=%.3f\n', ...
                stage,N,run,name,row.Sat,counts.ScoreCalls,counts.LocalInvocations,row.EndToEndSec);
        end
    end
end
assert(numel(rows)==numel(scales)*numel(run_indices)*4,'MCA:IncompleteShard');
fprintf('STRICT V2 %s SHARD COMPLETE rows=%d\n',stage,numel(rows));
end
function p=parameters(N,budget,repair,local)
p=struct('lr',0.1,'rho',0.01,'mu',1.05,'alpha',0.8, ...
    'pop_size',100,'deadline_scale',0.85,'max_gen',ceil(budget/100)+1, ...
    'local_search_prob',0.25,'alm_steps_per_gen',5,'guarded_local_search',true, ...
    'repair_aware_fitness',repair,'local_search_enabled',local,'score_budget',budget, ...
    'enable_internal_global_opt',false);
if N<100, p.lr=0.05; p.alpha=0.1; p.rho=1; p.deadline_scale=1; end
end
function r=row_template()
r=struct('SchemaVersion','','EvidenceClass','','N',0,'Run',0,'EnvironmentSeed',0, ...
    'SolverSeed',0,'Algorithm','','CandidateScoreBudget',0,'Sat',0,'Admission',0, ...
    'ResourceViolation',0,'SatisfiedCount',0,'AdmittedCount',0,'TaskCount',0, ...
    'RejectedCount',0,'MultiAssignedCount',0,'ScoreCalls',0,'EvaluatorCalls',0, ...
    'RepairCalls',0,'LocalInvocations',0,'InnerUpdates',0,'ChangedLocalGenes',0, ...
    'SolverAndRepairSec',0,'ReportingSec',0,'EndToEndSec',0);
end
