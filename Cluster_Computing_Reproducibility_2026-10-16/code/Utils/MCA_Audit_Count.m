function state = MCA_Audit_Count(action, value)
% Actual operations, not nominal generations. Persistent state is worker-local.
persistent s
if isempty(s) || strcmp(action, 'reset')
    s=struct('ScoreCalls',0,'EvaluatorCalls',0,'RepairCalls',0, ...
        'LocalInvocations',0,'InnerUpdates',0);
end
switch action
    case 'score', s.ScoreCalls=s.ScoreCalls+1;
    case 'evaluator', s.EvaluatorCalls=s.EvaluatorCalls+1;
    case 'repair', s.RepairCalls=s.RepairCalls+1;
    case 'local'
        s.LocalInvocations=s.LocalInvocations+1;
        s.InnerUpdates=s.InnerUpdates+value;
end
state=s;
end
