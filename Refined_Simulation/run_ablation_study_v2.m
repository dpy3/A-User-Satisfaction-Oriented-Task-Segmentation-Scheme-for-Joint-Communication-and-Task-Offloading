% RUN_ABLATION_STUDY_V2
% Rigorous Ablation Study to prove MA-ALM > GA and MA-ALM > Pure ALM
% Scenarios: N=50, N=80, N=100

clc; clear; close all;
rng('shuffle'); % Ensure Randomness

% Setup Scenarios
scenarios = [50, 80, 100];
num_runs = 5; % Monte Carlo
    
    results = struct();

for n_idx = 1:length(scenarios)
    N = scenarios(n_idx);
    fprintf('\n=== Running Scenario N=%d ===\n', N);
    
    % Storage
    sat_ma = zeros(num_runs, 1);
    sat_ga = zeros(num_runs, 1);
    sat_pure = zeros(num_runs, 1);
    
    for run = 1:num_runs
        fprintf('  Run %d/%d... ', run, num_runs);
        
        % Generate Independent Environment per Run (Rigorous)
        % Using the updated generate_tier1_env (Full Coverage, Congestion Bottleneck)
        [Task, Fog, Thing, DNN_Data] = generate_tier1_env(N, 5);
        
        % 1. MA-ALM (Proposed)
        % Pop=20, Gen=30, ALM_Steps=20 (Increased for deeper local search)
        opts_ma = struct('pop_size', 20, 'max_gen', 30, 'alm_steps', 20, 'elite_ratio', 0.2);
        [sol_ma, ~] = Memetic_ALM_Solver(Task, Fog, Thing, DNN_Data, opts_ma);
        [sat_ma(run), ~, ~, ~] = evaluate_solution(sol_ma, Task, Fog, Thing, DNN_Data, 0.01, false, 0);
        
        % 2. GA (Baseline)
        % Pop=50, Gen=50
        [sol_ga, ~] = GA_Solver_DNN_Vectorized(Task, Fog, Thing, DNN_Data, 50, 50);
        [sat_ga(run), ~, ~, ~] = evaluate_solution(sol_ga, Task, Fog, Thing, DNN_Data, 0.01, false, 0);
        
        % 3. Pure ALM (No GA, Random Init)
        % 500 Iterations
        [sol_pure, ~] = Pure_ALM_Solver(Task, Fog, Thing, DNN_Data, 500);
        [sat_pure(run), ~, ~, ~] = evaluate_solution(sol_pure, Task, Fog, Thing, DNN_Data, 0.01, false, 0);
        
        fprintf('MA=%.1f, GA=%.1f, Pure=%.1f\n', sat_ma(run), sat_ga(run), sat_pure(run));
    end
    
    results(n_idx).N = N;
    results(n_idx).MA_ALM = mean(sat_ma);
    results(n_idx).GA = mean(sat_ga);
    results(n_idx).Pure_ALM = mean(sat_pure);
    
    fprintf('  AVG Result N=%d: MA-ALM=%.2f%%, GA=%.2f%%, Pure-ALM=%.2f%%\n', ...
        N, mean(sat_ma), mean(sat_ga), mean(sat_pure));
end

% Save Results
save('Results_Ablation_Rigorous.mat', 'results');

% Plot Bar Chart
figure('Position', [100, 100, 800, 500]);
data = [[results.MA_ALM]; [results.GA]; [results.Pure_ALM]]';
b = bar(scenarios, data);
b(1).FaceColor = [0.8 0.2 0.2]; % Red for MA-ALM
b(2).FaceColor = [0.2 0.6 0.8]; % Blue for GA
b(3).FaceColor = [0.5 0.5 0.5]; % Grey for Pure ALM

legend('MA-ALM (Ours)', 'GA (Baseline)', 'Pure ALM (Gradient Only)', 'Location', 'NorthOutside', 'Orientation', 'horizontal');
xlabel('Number of Users (N)');
ylabel('Average User Satisfaction (%)');
title('Ablation Study: Contribution of Hybrid Optimization');
ylim([0 110]);
grid on;

% Add values on top
for i = 1:length(scenarios)
    text(i-0.25, data(i,1)+2, sprintf('%.1f', data(i,1)), 'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
    text(i,     data(i,2)+2, sprintf('%.1f', data(i,2)), 'HorizontalAlignment', 'center', 'FontSize', 9);
    text(i+0.25, data(i,3)+2, sprintf('%.1f', data(i,3)), 'HorizontalAlignment', 'center', 'FontSize', 9);
end

saveas(gcf, 'Fig_Ablation_Rigorous.png');
fprintf('Ablation Study Complete. Results saved.\n');
