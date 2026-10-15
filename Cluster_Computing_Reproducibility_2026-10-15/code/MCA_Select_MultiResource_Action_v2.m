function action = MCA_Select_MultiResource_Action_v2(policy, state, controller, cfg)
% Versioned action selector for PILOT3.  The v1 selector remains frozen.
if nargin < 4, cfg = struct(); end
if ~isfield(cfg,'intervention_budget'), cfg.intervention_budget=0.25; end
if ~isfield(cfg,'pressure_target'), cfg.pressure_target=0.85; end
if ~isfield(cfg,'lyapunov_V'), cfg.lyapunov_V=1.0; end
actions = candidate_actions(state,cfg.intervention_budget);
name = upper(char(policy));
switch name
    case 'NOACTION'
        action=actions(1);
    case 'FIXEDMATCHEDV2'
        full=find([actions.IsFullCapacity]);
        [gain,local]=max([actions(full).NetGain]);
        % The v2 fixed comparator uses the same action-specific observability
        % as the adaptive controllers, but always takes the best full action.
        if gain>0, action=actions(full(local)); else, action=actions(1); end
    case 'MPCMRV2'
        scores=zeros(numel(actions),1); trend=zeros(1,4);
        if isfield(controller,'PreviousPressure') && ~isempty(controller.PreviousPressure)
            trend=state.Vector-controller.PreviousPressure;
        end
        for a=1:numel(actions), scores(a)=mpc_score(actions(a),state,trend,cfg); end
        [~,idx]=min(scores); action=actions(idx);
    case 'LYAPUNOVMRV2'
        service_q=get_field(controller,'VirtualSLAQueue',0);
        cost_q=get_field(controller,'VirtualCostQueue',0);
        scores=zeros(numel(actions),1);
        for a=1:numel(actions)
            scores(a)=-(10+service_q)*actions(a).NetGain + ...
                (cfg.lyapunov_V+cost_q)*actions(a).CostUnits;
        end
        [~,idx]=min(scores); action=actions(idx);
    otherwise
        error('MCA:UnknownMultiResourcePolicyV2','Unknown v2 policy: %s',policy);
end
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
idx=resource_index(action.Resource);
resource_gain=0;
if idx>0
    if action.BoostFactor>=1.2, resource_gain=state.ActionGainFull(idx);
    else, resource_gain=state.ActionGainHalf(idx); end
end
% Rejection has no asserted immediate service gain.  Any future queue benefit
% must be established by a separate transition model before it can offset the
% explicit loss of rejected demand.
action.ModelGain=min(1,resource_gain);
action.DirectLoss=action.RejectFraction*state.ArrivalFraction;
action.NetGain=action.ModelGain-action.DirectLoss;
end

function score=mpc_score(action,state,trend,cfg)
score=action.CostUnits+3*action.DirectLoss;
for h=1:3
    forecast=max(0,state.Vector+h*trend); adjusted=forecast;
    adjusted(1:3)=adjusted(1:3)*(1-action.RejectFraction);
    idx=resource_index(action.Resource);
    if idx>0, adjusted(idx)=adjusted(idx)/action.BoostFactor; end
    overload=max(adjusted(1:3)/cfg.pressure_target-1,0);
    queue_over=max(adjusted(4)/0.8-1,0);
    score=score+sum(overload.^2)+queue_over^2;
end
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
