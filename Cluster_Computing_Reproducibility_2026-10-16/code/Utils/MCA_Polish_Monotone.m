function [theta, diag] = MCA_Polish_Monotone(theta, Pre, Fog, Task, DNN_Data, passes)
% Optional sensitivity only. Every move uses the reporting evaluator globally.
% No separate 0.999 cutoff, node-local safety proxy, or random tie handling.
if nargin < 6, passes = 1; end
[N,M]=size(theta);
assert(all(sum(theta>0,2)<=1), 'MCA:InvalidPolishInput');
diag=struct('Evaluations',0,'AcceptedMoves',0,'SatBefore',0,'SatAfter',0);
[key,sat]=objective(theta); diag.SatBefore=sat;
for pass=1:passes
    changed=false;
    for i=1:N
        current=find(theta(i,:)>0);
        if isempty(current), continue; end
        for j=1:M
            if j==current, continue; end
            trial=theta; trial(i,:)=0; trial(i,j)=1;
            [candidate,~]=objective(trial);
            % Feasibility first; global satisfied count never falls once feasible.
            if lex_better(candidate,key)
                theta=trial; key=candidate; current=j;
                diag.AcceptedMoves=diag.AcceptedMoves+1;
                changed=true;
            end
        end
    end
    if ~changed, break; end
end
[~,sat]=objective(theta); diag.SatAfter=sat;
assert(diag.SatAfter+1e-12>=diag.SatBefore, 'MCA:PolishSatRegression');
    function [k,sat] = objective(t)
        [sat,~,b,lat]=calculate_metrics_v2(t,Task,Fog,[],DNN_Data,Pre,true);
        diag.Evaluations=diag.Evaluations+1;
        k=[-b.resource_viol_rate,sat,-sum(lat(isfinite(lat)))];
    end
end
function tf=lex_better(a,b)
tf=false;
for k=1:numel(a)
    if a(k)>b(k)+1e-12, tf=true; return; end
    if a(k)<b(k)-1e-12, return; end
end
end
