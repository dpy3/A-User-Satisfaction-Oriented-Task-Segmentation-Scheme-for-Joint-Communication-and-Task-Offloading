function Probe_MCA_Latency_Comm_v2_Capacity()
% Joint capacity probe on independent runs 76--80.
cfg=MCA_Official_Setup('audit'); runs=76:80; sample_n=3000;
scales=[0.0004,0.0005,0.000625,0.0008,0.001,0.00125,0.0016,0.002, ...
    0.0025,0.0032,0.004,0.005];
root=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'LATENCY_COMM_V2_PROFILE_CALIBRATION');
rows=repmat(row_template(),0,1);
for run=runs
    seed=cfg.seed_base+1000*run; rng(seed,'twister');
    [Task,base_fog,Thing,DNN_Data]=generate_tier1_env_trace(sample_n,cfg.fog_num_fixed);
    for scale=scales
        Fog=base_fog; Fog(:,6)=Fog(:,6)*scale;
        Pre=build_pre_struct_tier1(Task,Fog,Thing,DNN_Data);
        [capacity,diag]=estimate_capacity_lp(Task,Fog,DNN_Data,Pre);
        row=row_template(); row.Run=run; row.Seed=seed; row.SampleN=sample_n;
        row.BandwidthScale=scale; row.CapacityEstimate=capacity;
        row.LatencyExcludedPairs=diag.LatencyExcludedPairs;
        row.FeasibleTaskTypes=diag.FeasibleTaskTypes;
        row.AllTaskTypesFeasible=diag.FeasibleTaskTypes==3;
        row.PositiveCapacity=isfinite(capacity) && capacity>=1;
        rows(end+1)=row; %#ok<AGROW>
    end
end
tbl=struct2table(rows);
writetable(tbl,fullfile(root,'LatencyCommV2_Capacity_Probe.csv'));
summary=repmat(summary_template(),0,1);
for scale=scales
    block=tbl(abs(tbl.BandwidthScale-scale)<1e-12,:);
    row=summary_template(); row.BandwidthScale=scale; row.Runs=height(block);
    row.MedianCapacity=median(block.CapacityEstimate);
    row.MinCapacity=min(block.CapacityEstimate); row.MaxCapacity=max(block.CapacityEstimate);
    row.MedianLatencyExcludedPairs=median(block.LatencyExcludedPairs);
    row.AllTaskTypesFeasibleRuns=sum(block.AllTaskTypesFeasible);
    row.PositiveCapacityRuns=sum(block.PositiveCapacity);
    row.CapacityGate=all(block.AllTaskTypesFeasible & block.PositiveCapacity);
    summary(end+1)=row; %#ok<AGROW>
end
summary_tbl=struct2table(summary);
writetable(summary_tbl,fullfile(root,'LatencyCommV2_Capacity_Summary.csv'));
fprintf('LATENCY COMM V2 CAPACITY PROBE COMPLETE: %d rows.\n',height(tbl));
disp(summary_tbl);
end

function row=row_template()
row=struct('Run',0,'Seed',0,'SampleN',0,'BandwidthScale',0, ...
    'CapacityEstimate',0,'LatencyExcludedPairs',0,'FeasibleTaskTypes',0, ...
    'AllTaskTypesFeasible',false,'PositiveCapacity',false);
end

function row=summary_template()
row=struct('BandwidthScale',0,'Runs',0,'MedianCapacity',0,'MinCapacity',0, ...
    'MaxCapacity',0,'MedianLatencyExcludedPairs',0, ...
    'AllTaskTypesFeasibleRuns',0,'PositiveCapacityRuns',0,'CapacityGate',false);
end

function [capacity,diag]=estimate_capacity_lp(Task,Fog,DNN_Data,Pre)
M=size(Fog,1); T=3; mix=[0.4;0.3;0.3]; mean_deadline=mean(Task(:,3));
comp=zeros(T,M); comm=zeros(T,M); deadline=zeros(T,1); mem=zeros(T,1);
for t=1:T
    mask=Task(:,2)==t; assert(any(mask),'MCA:LatencyV2SampleMix','Missing task type %d.',t);
    comp(t,:)=mean(Pre.Comp(mask,:),1); comm(t,:)=mean(Pre.Comm(mask,:),1);
    deadline(t)=mean(Task(mask,3)); mem(t)=task_memory_mb(t,DNN_Data);
end
feasible_pairs=comm+comp<=deadline;
vars=T*M+1; k_idx=vars; f=zeros(vars,1); f(k_idx)=-1;
Aeq=zeros(T,vars);
for t=1:T
    Aeq(t,(t-1)*M+(1:M))=1; Aeq(t,k_idx)=-mix(t);
end
A=zeros(2*M,vars); b=zeros(2*M,1);
for node=1:M
    for t=1:T
        idx=(t-1)*M+node; A(node,idx)=comp(t,node); A(M+node,idx)=mem(t);
    end
    b(node)=0.99*mean_deadline; b(M+node)=Fog(node,8);
end
lb=zeros(vars,1); ub=inf(vars,1);
for t=1:T
    for node=1:M
        if ~feasible_pairs(t,node), ub((t-1)*M+node)=0; end
    end
end
options=optimoptions('linprog','Display','none');
[x,~,exitflag]=linprog(f,A,b,Aeq,zeros(T,1),lb,ub,options);
if exitflag>0 && ~isempty(x), capacity=x(k_idx); else, capacity=0; end
diag=struct('LatencyExcludedPairs',sum(~feasible_pairs,'all'), ...
    'FeasibleTaskTypes',sum(any(feasible_pairs,2)));
end

function value=task_memory_mb(t,DNN_Data)
if isnumeric(DNN_Data)
    row=4-t; value=DNN_Data(row,1)+DNN_Data(row,2);
elseif iscell(DNN_Data)
    value=sum(DNN_Data{t}.data);
else
    value=sum(DNN_Data(t).data);
end
end
