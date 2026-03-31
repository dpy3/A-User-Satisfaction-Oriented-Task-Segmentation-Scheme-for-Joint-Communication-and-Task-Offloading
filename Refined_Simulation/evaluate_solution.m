function [avg_satis, avg_lat, avg_energy, viol_rate, D_T, S_t] = evaluate_solution(theta, Task, Fog, Thing, DNN_Data, overhead_base, is_plot, solver_time)
    if nargin < 6 || isempty(overhead_base), overhead_base = 0.01; end
    if nargin < 7 || isempty(is_plot), is_plot = false; end
    if nargin < 8 || isempty(solver_time), solver_time = 0; end

    [avg_satis, viol_rate, breakdown, D_T, S_t] = calculate_metrics_v2(theta, Task, Fog, Thing, DNN_Data);
    avg_lat = sum(breakdown) + solver_time;
    [avg_energy, ~] = calculate_energy_advanced_v2(theta, Task, Fog, Thing, DNN_Data);
end
