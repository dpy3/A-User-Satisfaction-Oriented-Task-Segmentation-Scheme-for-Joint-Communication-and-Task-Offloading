function [sat, resource_viol] = MCA_Selection_Score(theta, Pre, Task, Fog, DNN_Data)
MCA_Audit_Count('score');
% Candidate revision only. Share reporting evaluator; rejects never earn satisfaction.
% Scores are fractions. Feasibility is resource violation, not deadline failure.
[sat_percent, ~, b] = calculate_metrics_v2(theta, Task, Fog, [], DNN_Data, Pre, true);
sat = sat_percent / 100;
resource_viol = b.resource_viol_rate / 100;
end

