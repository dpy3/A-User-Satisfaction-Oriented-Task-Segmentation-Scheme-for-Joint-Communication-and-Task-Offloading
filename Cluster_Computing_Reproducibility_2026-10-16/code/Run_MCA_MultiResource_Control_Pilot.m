function Run_MCA_MultiResource_Control_Pilot(mode,profile_filter,shard_id)
if nargin<1 || isempty(mode), mode='smoke'; end
protocol=pilot_config(mode);
if nargin>=2 && ~isempty(profile_filter)
    requested=string(profile_filter);
    mask=ismember(protocol.profiles,requested);
    assert(any(mask) && sum(mask)==numel(requested),'MCA:UnknownMRProfile', ...
        'Profile filter contains an unknown or duplicate profile.');
    protocol.profiles=protocol.profiles(mask);
    protocol.loads=protocol.loads(mask);
    protocol.profile_ids=protocol.profile_ids(mask);
end
if nargin>=3 && ~isempty(shard_id)
    safe_id=regexprep(char(string(shard_id)),'[^A-Za-z0-9_-]','_');
    protocol.results_dir=fullfile(protocol.results_dir,'SHARDS',safe_id);
end
if startsWith(protocol.mode,'smoke')
    solver_mode='audit';
else
    solver_mode='selectorefficientpilot';
end
cfg=MCA_Official_Setup(solver_mode);
if ~exist(protocol.results_dir,'dir'), mkdir(protocol.results_dir); end
capacity_file=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'CAPACITYPHASEPILOT_FIXED5','Capacity_Reference_Frozen.csv');
assert(exist(capacity_file,'file')==2,'MCA:MissingCapacityReference', ...
    'Missing frozen capacity reference: %s',capacity_file);
capacity=readtable(capacity_file,'TextType','string');
if ismember(protocol.mode,{'smoke4','smoke5','smoke6','pilot3','pilot4'})
    new_capacity_file=fullfile(fileparts(mfilename('fullpath')),'Results', ...
        'CAPACITYPHASELATENCYISOLATEDV3FINAL_FIXED5','Capacity_Reference_Frozen.csv');
    assert(exist(new_capacity_file,'file')==2,'MCA:MissingIsolatedV3Capacity', ...
        'Missing isolated-v3 capacity reference.');
    capacity=[capacity;readtable(new_capacity_file,'TextType','string')];
end
sla_file=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'CAPACITYPHASEPILOT_FIXED5','CapacityPhase_Analysis','CapacityPhase_Summary.csv');
assert(exist(sla_file,'file')==2,'MCA:MissingSLACalibration', ...
    'Missing frozen SLA calibration: %s',sla_file);
sla_calibration=readtable(sla_file,'TextType','string');
sla_calibration_v3=table();
if ismember(protocol.mode,{'smoke4','smoke5','smoke6','pilot3','pilot4'})
    new_sla_file=fullfile(fileparts(mfilename('fullpath')),'Results', ...
        'CAPACITYPHASELATENCYISOLATEDV3SLA_FIXED5','LatencyCommIsolatedV3_SLA_Frozen.csv');
    assert(exist(new_sla_file,'file')==2,'MCA:MissingIsolatedV3SLA', ...
        'Missing isolated-v3 SLA calibration.');
    sla_calibration_v3=readtable(new_sla_file,'TextType','string');
end
rows=repmat(row_template(),0,1);
checkpoint=fullfile(protocol.results_dir,'MultiResource_Control_Checkpoint.mat');
if exist(checkpoint,'file')==2, saved=load(checkpoint,'rows'); rows=saved.rows; end
for p=1:numel(protocol.profiles)
    profile=protocol.profiles(p); ref=capacity(capacity.Profile==profile,:);
    profile_id=protocol.profile_ids(p);
    C=ref.CapacityRef(1); lambda=protocol.loads(p); N=max(1,round(C*lambda));
    profile_protocol=protocol;
    if profile=="latency_comm_isolated_v3"
        profile_protocol.sla_target=calibrated_sla_target(sla_calibration_v3,profile,lambda);
    else
        profile_protocol.sla_target=calibrated_sla_target(sla_calibration,profile,lambda);
    end
    for run=protocol.runs
        if complete(rows,profile,run,protocol.policies), continue; end
        rows=remove_partial(rows,profile,run);
        states=initialize_states(protocol.policies);
        acc=repmat(accumulator(),1,numel(protocol.policies));
        for slot=1:protocol.slots
            seed=cfg.seed_base+300000000+10000000*profile_id+1000*run+slot;
            rng(seed,'twister');
            [arr_task,base_fog,arr_thing,DNN_Data]=generate_tier1_env_trace(N,cfg.fog_num_fixed);
            [base_fog,~]=MCA_Apply_Infrastructure_Profile(base_fog,profile);
            for a=1:numel(protocol.policies)
                policy=protocol.policies{a}; pending=states.(policy);
                offered_task=[pending.Task;arr_task]; offered_thing=[pending.Thing;arr_thing];
                offered_task(:,1)=(1:size(offered_task,1))';
                resource=MCA_MultiResource_State(offered_task,base_fog,offered_thing,DNN_Data, ...
                    size(pending.Task,1),N);
                if ismember(protocol.mode,{'smoke6','pilot4'})
                    action=MCA_Select_MultiResource_Action_v3(policy,resource,pending.Controller,profile_protocol);
                elseif ismember(protocol.mode,{'smoke3','smoke3b','smoke3c','smoke4','smoke5','pilot3'})
                    action=MCA_Select_MultiResource_Action_v2(policy,resource,pending.Controller,profile_protocol);
                else
                    action=MCA_Select_MultiResource_Action(policy,resource,pending.Controller,profile_protocol);
                end
                [Task,Thing,Fog,rejects]=apply_action(action,pending,arr_task,arr_thing,base_fog,DNN_Data);
                Pre=build_pre_struct_tier1(Task,Fog,Thing,DNN_Data); Pre.Mean_Deadline=mean(Task(:,3));
                Pre.Violation_Mode=cfg.violation_mode; Pre.BacklogIn=size(pending.Task,1);
                Pre.Arrivals=size(arr_task,1); Pre.ReplayScaleN=N; Pre.FullBacklogStreak=pending.FullBacklogStreak;
                rng(seed+4000,'twister'); t0=tic;
                theta=MCA_Solve('ALMv9',Task,Fog,Thing,DNN_Data,Pre,cfg); runtime=toc(t0);
                m=MCA_Evaluate(theta,Task,Fog,Thing,DNN_Data,Pre,'multi-resource-pilot');
                assert(m.ResourceViolation==0,'MCA:MRResourceViolation','Post-repair violation.');
                unresolved=m.SatisfiedVector<.5; cap=N;
                keep_count=min(sum(unresolved),cap);
                if keep_count==0
                    keep=zeros(0,1);
                else
                    keep=find(unresolved,keep_count,'first');
                end
                queue_drops=max(0,sum(unresolved)-cap);
                offered=size(pending.Task,1)+size(arr_task,1);
                sat=100*m.SatisfiedCount/max(1,offered);
                states.(policy).Task=Task(keep,:); states.(policy).Thing=Thing(keep,:);
                states.(policy).FullBacklogStreak=update_streak(numel(keep),cap,pending.FullBacklogStreak);
                states.(policy).Controller=update_controller(pending.Controller,resource,action,sat,profile_protocol);
                acc(a).Sat=acc(a).Sat+sat; acc(a).Satisfied=acc(a).Satisfied+m.SatisfiedCount;
                acc(a).Rejects=acc(a).Rejects+rejects; acc(a).QueueDrops=acc(a).QueueDrops+queue_drops;
                acc(a).Backlog=acc(a).Backlog+numel(keep); acc(a).Cost=acc(a).Cost+action.CostUnits;
                acc(a).Runtime=acc(a).Runtime+runtime; acc(a).Actions=acc(a).Actions+double(action.Name~="none");
                acc(a)=record_action(acc(a),action);
            end
        end
        for a=1:numel(protocol.policies)
            rows(end+1)=make_row(profile_protocol,profile,lambda,C,N,run,protocol.policies{a},acc(a)); %#ok<AGROW>
        end
        save(checkpoint,'rows','protocol'); fprintf('%s run=%d complete\n',profile,run);
    end
end
tbl=struct2table(rows); output=fullfile(protocol.results_dir,'MultiResource_Control_RunLevel.csv');
writetable(tbl,output); validate(tbl,protocol);
fprintf('MULTI-RESOURCE CONTROL %s PASS: %s\n',upper(protocol.mode),output);
end

function p=pilot_config(mode)
p.mode=lower(char(mode)); p.profiles=["compute_bound","memory_bound","latency_filtered"];
p.profile_ids=1:numel(p.profiles);
p.loads=[.55,1.0,.55];
if ismember(p.mode,{'smoke4','smoke5','smoke6','pilot3','pilot4'})
    p.profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    p.profile_ids=[1,2,6]; p.loads=[.55,1.0,.05];
end
if ismember(p.mode,{'smoke6','pilot4'})
    p.policies={'NoAction','FixedMatchedV2','MPCMRV2','LyapunovMRv3'};
elseif ismember(p.mode,{'smoke3','smoke3b','smoke3c','smoke4','smoke5','pilot3'})
    p.policies={'NoAction','FixedMatchedV2','MPCMRV2','LyapunovMRv2'};
else
    p.policies={'NoAction','FixedMatched','MPCMR','LyapunovMR'};
end
p.intervention_budget=.25; p.average_cost_target=.125; p.pressure_target=.85;
p.lyapunov_V=1; p.rejection_penalty=1.0;
switch p.mode
    case {'smoke','smoke2'}, p.runs=1:2; p.slots=20;
    case 'smoke3', p.runs=101:102; p.slots=20;
    case 'smoke3b', p.runs=103:104; p.slots=20;
    case 'smoke3c', p.runs=105:106; p.slots=20;
    case 'smoke4', p.runs=201:202; p.slots=20;
    case 'smoke5', p.runs=203:204; p.slots=20;
    case 'smoke6', p.runs=205:206; p.slots=20;
    case 'pilot', p.runs=1:5; p.slots=100;
    case 'pilot2', p.runs=6:10; p.slots=100;
    case 'pilot3', p.runs=11:15; p.slots=100;
    case 'pilot4', p.runs=16:20; p.slots=100;
    otherwise, error('MCA:UnknownMRMode','Unknown mode: %s',mode);
end
p.results_dir=fullfile(fileparts(mfilename('fullpath')),'Results',['MULTIRESOURCE_' upper(p.mode)]);
end

function states=initialize_states(policies)
states=struct();
for i=1:numel(policies)
    states.(policies{i})=struct('Task',zeros(0,6),'Thing',zeros(0,6), ...
        'FullBacklogStreak',0,'Controller',struct('VirtualSLAQueue',0, ...
        'VirtualCostQueue',0,'PreviousPressure',[]));
end
end

function [Task,Thing,Fog,rejects]=apply_action(action,pending,arr_task,arr_thing,Fog,DNN_Data)
keep_count=max(0,floor((1-action.RejectFraction)*size(arr_task,1)));
if keep_count<size(arr_task,1)
    Pre=build_pre_struct_tier1(arr_task,Fog,arr_thing,DNN_Data);
    [best,~]=min(Pre.Comp+Pre.Comm,[],2); [~,order]=sort(best,'ascend'); keep=sort(order(1:keep_count));
else
    keep=(1:size(arr_task,1))';
end
rejects=size(arr_task,1)-numel(keep); Task=[pending.Task;arr_task(keep,:)];
Thing=[pending.Thing;arr_thing(keep,:)]; Task(:,1)=(1:size(Task,1))';
switch action.Resource
    case "compute", Fog(:,[4,7])=Fog(:,[4,7])*action.BoostFactor;
    case "memory", Fog(:,8)=Fog(:,8)*action.BoostFactor;
    case "bandwidth", Fog(:,6)=Fog(:,6)*action.BoostFactor;
end
end

function c=update_controller(c,resource,action,sat,p)
c.VirtualSLAQueue=max(0,c.VirtualSLAQueue+p.sla_target-sat/100);
c.VirtualCostQueue=max(0,c.VirtualCostQueue+action.CostUnits-p.average_cost_target);
c.PreviousPressure=resource.Vector;
end

function value=update_streak(backlog,cap,previous)
if backlog>=cap && cap>0, value=previous+1; else, value=0; end
end

function a=accumulator()
a=struct('Sat',0,'Satisfied',0,'Rejects',0,'QueueDrops',0,'Backlog',0, ...
    'Cost',0,'Runtime',0,'Actions',0,'AdmissionActions',0, ...
    'CapacityActions',0,'HybridActions',0,'ComputeActions',0, ...
    'MemoryActions',0,'BandwidthActions',0);
end

function row=row_template()
row=struct('Mode',"",'Profile',"",'NormalizedLoad',0,'CapacityRef',0,'N',0, ...
    'Run',0,'Policy',"",'Slots',0,'SLATarget',0,'MeanSat',0,'TotalSatisfied',0, ...
    'AdmissionRejects',0,'QueueDrops',0,'BacklogAUC',0,'InterventionCostUnits',0, ...
    'ActiveSlots',0,'AdmissionActions',0,'CapacityActions',0,'HybridActions',0, ...
    'ComputeActions',0,'MemoryActions',0,'BandwidthActions',0,'RuntimeSec',0);
end

function row=make_row(p,profile,lambda,C,N,run,policy,a)
row=row_template(); row.Mode=upper(string(p.mode)); row.Profile=profile;
row.NormalizedLoad=lambda; row.CapacityRef=C; row.N=N; row.Run=run;
row.Policy=string(policy); row.Slots=p.slots; row.SLATarget=p.sla_target;
row.MeanSat=a.Sat/p.slots;
row.TotalSatisfied=a.Satisfied; row.AdmissionRejects=a.Rejects; row.QueueDrops=a.QueueDrops;
row.BacklogAUC=a.Backlog; row.InterventionCostUnits=a.Cost; row.ActiveSlots=a.Actions;
row.AdmissionActions=a.AdmissionActions; row.CapacityActions=a.CapacityActions;
row.HybridActions=a.HybridActions; row.ComputeActions=a.ComputeActions;
row.MemoryActions=a.MemoryActions; row.BandwidthActions=a.BandwidthActions;
row.RuntimeSec=a.Runtime;
end

function a=record_action(a,action)
switch action.Name
    case "admission", a.AdmissionActions=a.AdmissionActions+1;
    case {"targeted_capacity","targeted_capacity_full","targeted_capacity_half"}
        a.CapacityActions=a.CapacityActions+1;
    case "hybrid", a.HybridActions=a.HybridActions+1;
end
switch action.Resource
    case "compute", a.ComputeActions=a.ComputeActions+1;
    case "memory", a.MemoryActions=a.MemoryActions+1;
    case "bandwidth", a.BandwidthActions=a.BandwidthActions+1;
end
end

function target=calibrated_sla_target(tbl,profile,lambda)
mask=tbl.Profile==profile & tbl.Algorithm=="ALMv9" & ...
    abs(tbl.NormalizedLoadTarget-lambda)<1e-9;
row=tbl(mask,:);
assert(height(row)==1,'MCA:AmbiguousSLACalibration', ...
    'Expected one frozen SLA calibration row for %s at load %.3f.',profile,lambda);
target=row.MeanSat(1)/100;
assert(isfinite(target) && target>0 && target<=1,'MCA:InvalidSLACalibration', ...
    'Invalid SLA target %.6f for %s.',target,profile);
end

function tf=complete(rows,profile,run,policies)
if isempty(rows),tf=false;return;end
mask=string({rows.Profile})==profile & [rows.Run]==run;
tf=isequal(sort(string({rows(mask).Policy})),sort(string(policies)));
end

function rows=remove_partial(rows,profile,run)
if isempty(rows),return;end
mask=string({rows.Profile})==profile & [rows.Run]==run; rows(mask)=[];
end

function validate(tbl,p)
expected=numel(p.profiles)*numel(p.runs)*numel(p.policies);
assert(height(tbl)==expected,'MCA:MRIncomplete','Expected %d rows, found %d.',expected,height(tbl));
assert(all(tbl.InterventionCostUnits<=p.slots*p.intervention_budget+1e-9), ...
    'MCA:MRBudget','A controller exceeded the matched intervention budget.');
end
