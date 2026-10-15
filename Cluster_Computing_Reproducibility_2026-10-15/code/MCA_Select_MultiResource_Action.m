function action = MCA_Select_MultiResource_Action(policy, resource_state, controller_state, cfg)
if nargin < 4, cfg = struct(); end
if ~isfield(cfg,'intervention_budget'), cfg.intervention_budget=0.25; end
if ~isfield(cfg,'pressure_target'), cfg.pressure_target=0.85; end
if ~isfield(cfg,'lyapunov_V'), cfg.lyapunov_V=1.0; end
if ~isfield(cfg,'rejection_penalty'), cfg.rejection_penalty=1.0; end
actions = candidate_actions(resource_state, cfg.intervention_budget);
name = upper(char(policy));
switch name
    case 'NOACTION'
        action = actions(1);
    case 'FIXEDMATCHED'
        if max(resource_state.Vector(1:3)) > cfg.pressure_target || resource_state.QueuePressure > 0.5
            action = actions(end);
        else
            action = actions(1);
        end
    case 'MPCMR'
        scores=zeros(numel(actions),1);
        trend=zeros(1,4);
        if isfield(controller_state,'PreviousPressure') && ~isempty(controller_state.PreviousPressure)
            trend=resource_state.Vector-controller_state.PreviousPressure;
        end
        for a=1:numel(actions)
            scores(a)=mpc_score(actions(a),resource_state.Vector,trend,cfg);
        end
        [~,idx]=min(scores); action=actions(idx);
    case 'LYAPUNOVMR'
        virtual_q=get_field(controller_state,'VirtualSLAQueue',0);
        cost_q=get_field(controller_state,'VirtualCostQueue',0);
        scores=zeros(numel(actions),1);
        for a=1:numel(actions)
            adjusted=apply_pressure_model(resource_state.Vector,actions(a));
            pressure_loss=sum(max(adjusted(1:3)-cfg.pressure_target,0).^2)+ ...
                max(adjusted(4)-0.8,0)^2;
            service_loss=cfg.rejection_penalty*actions(a).RejectFraction;
            scores(a)=(10+virtual_q)*(pressure_loss+service_loss)+ ...
                cfg.lyapunov_V*actions(a).CostUnits+cost_q*actions(a).CostUnits;
        end
        [~,idx]=min(scores); action=actions(idx);
    otherwise
        error('MCA:UnknownMultiResourcePolicy','Unknown policy: %s',policy);
end
end

function actions = candidate_actions(state,budget)
[~,resource_idx]=max(state.Vector(1:3)); names=["compute","memory","bandwidth"];
target=names(resource_idx);
actions=repmat(template(),5,1);
actions(1)=make("none","none",1,0,0);
actions(2)=make("admission","none",1,budget,budget);
actions(3)=make("targeted_capacity",target,1+budget,0,budget);
actions(4)=make("targeted_capacity_half",target,1+budget/2,0,budget/2);
actions(5)=make("hybrid",target,1+budget/2,budget/2,budget);
end

function value = mpc_score(action,current,trend,cfg)
value=action.CostUnits;
for h=1:3
    forecast=max(0,current+h*trend);
    adjusted=apply_pressure_model(forecast,action);
    pressure_loss=sum(max(adjusted(1:3)-cfg.pressure_target,0).^2)+ ...
        max(adjusted(4)-0.8,0)^2;
    value=value+pressure_loss+cfg.rejection_penalty*action.RejectFraction;
end
end

function adjusted = apply_pressure_model(values,action)
adjusted=values;
arrival_factor=max(0.5,1-action.RejectFraction);
adjusted(1:3)=adjusted(1:3)*arrival_factor;
switch action.Resource
    case "compute", adjusted(1)=adjusted(1)/action.BoostFactor;
    case "memory", adjusted(2)=adjusted(2)/action.BoostFactor;
    case "bandwidth", adjusted(3)=adjusted(3)/action.BoostFactor;
end
end

function out = template()
out=struct('Name',"none",'Resource',"none",'BoostFactor',1, ...
    'RejectFraction',0,'CostUnits',0);
end

function out = make(name,resource,boost,reject,cost)
out=template(); out.Name=name; out.Resource=resource; out.BoostFactor=boost;
out.RejectFraction=reject; out.CostUnits=cost;
end

function value = get_field(s,name,default)
value=default; if isfield(s,name), value=s.(name); end
end
