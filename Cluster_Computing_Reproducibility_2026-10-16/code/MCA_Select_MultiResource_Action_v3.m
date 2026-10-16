function action = MCA_Select_MultiResource_Action_v3(policy, state, controller, cfg)
% Service-safe selector pre-registered for PILOT4. V1 and v2 stay frozen.
if nargin < 4, cfg=struct(); end
if ~strcmpi(policy,'LyapunovMRv3')
    action=MCA_Select_MultiResource_Action_v2(policy,state,controller,cfg);
    return;
end
if ~isfield(cfg,'intervention_budget'), cfg.intervention_budget=0.25; end
if ~isfield(cfg,'lyapunov_V'), cfg.lyapunov_V=1.0; end
actions=candidate_actions(state,cfg.intervention_budget);
full=find([actions.IsFullCapacity]);
[anchor_gain,local]=max([actions(full).NetGain]);
anchor=full(local);
if anchor_gain<=0
    action=actions(1);
    return;
end

service_q=get_field(controller,'VirtualSLAQueue',0);
if service_q>0
    action=actions(anchor);
    return;
end

% With no accumulated SLA deficit, minimize drift-plus-penalty only inside
% the no-rejection set whose modeled service is machine-equivalent to the
% fixed full-capacity anchor.
cost_q=get_field(controller,'VirtualCostQueue',0);
tol=16*eps(max(1,abs(anchor_gain)));
safe=find([actions.RejectFraction]==0 & [actions.NetGain]>=anchor_gain-tol);
scores=([actions(safe).CostUnits]*(cfg.lyapunov_V+cost_q))';
ranking=sortrows([scores,-[actions(safe).NetGain]',safe'],[1,2,3]);
action=actions(ranking(1,3));
end

function actions=candidate_actions(state,budget)
resources=["compute","memory","bandwidth"];
actions=repmat(template(),11,1); k=1;
actions(k)=make("none","none",1,0,0,false); k=k+1;
actions(k)=make("admission","none",1,budget,budget,false); k=k+1;
for i=1:3
    actions(k)=make("targeted_capacity_full",resources(i),1+budget,0,budget,true); k=k+1;
end
for i=1:3
    actions(k)=make("targeted_capacity_half",resources(i),1+budget/2,0,budget/2,false); k=k+1;
end
for i=1:3
    actions(k)=make("hybrid",resources(i),1+budget/2,budget/2,budget,false); k=k+1;
end
for a=1:numel(actions), actions(a)=annotate(actions(a),state); end
end

function action=annotate(action,state)
idx=resource_index(action.Resource); resource_gain=0;
if idx>0
    if action.BoostFactor>=1.2, resource_gain=state.ActionGainFull(idx);
    else, resource_gain=state.ActionGainHalf(idx); end
end
action.ModelGain=min(1,resource_gain);
action.DirectLoss=action.RejectFraction*state.ArrivalFraction;
action.NetGain=action.ModelGain-action.DirectLoss;
end

function idx=resource_index(resource)
switch resource
    case "compute", idx=1;
    case "memory", idx=2;
    case "bandwidth", idx=3;
    otherwise, idx=0;
end
end

function out=template()
out=struct('Name',"none",'Resource',"none",'BoostFactor',1, ...
    'RejectFraction',0,'CostUnits',0,'ModelGain',0,'DirectLoss',0, ...
    'NetGain',0,'IsFullCapacity',false);
end

function out=make(name,resource,boost,reject,cost,is_full)
out=template(); out.Name=name; out.Resource=resource; out.BoostFactor=boost;
out.RejectFraction=reject; out.CostUnits=cost; out.IsFullCapacity=is_full;
end

function value=get_field(s,name,default)
value=default; if isfield(s,name), value=s.(name); end
end
