% PLOT_PUBLICATION_FIGURES
% 
% Generates publication-quality figures for IEEE/ACM Transactions.
% Reads data from 'Results_Final_Publication/'.

clc; clear; close all;

% --- Config ---
RESULTS_DIR = 'Results_Final_Publication';
EXPORT_DIR = '../../../ACM-trans/figures';
if ~exist(EXPORT_DIR, 'dir'), mkdir(EXPORT_DIR); end

% Colors (Colorblind Safe / Professional)
% Matching: Local, Greedy, GA, GA-Hybrid, Memetic-ALM
colors = [
    0.2, 0.2, 0.2;   % Local (Dark Grey)
    0.5, 0.5, 0.5;   % Greedy (Gray)
    0.0, 0.45, 0.74; % GA (Blue)
    0.85, 0.33, 0.1; % GA-Hybrid (Orange)
    0.0, 0.6, 0.0;   % Memetic-ALM (Green - Strong)
];

line_styles = {'--', ':', '-.', '--', '-'}; % MA-ALM is solid
markers = {'o', 'x', 's', 'd', 'p'}; % MA-ALM is pentagram

% --- Figure 1: Scalability Analysis (Combined) ---
results_file = fullfile(RESULTS_DIR, 'results_scale_final.mat');
if ~exist(results_file, 'file')
    results_file = fullfile(RESULTS_DIR, 'results_scale_checkpoint.mat');
    fprintf('Warning: Using checkpoint data for plotting.\n');
end
load(results_file); % Load results_scale, N_RANGE, ALGORITHMS

h_fig1 = figure('Units', 'pixels', 'Position', [100, 100, 1200, 800], 'Color', 'w');

% 1. Satisfaction
subplot(2, 2, 1); hold on; grid on;
for i = 1:length(ALGORITHMS)
    data = squeeze(results_scale.sat(:, i, :));
    mu = mean(data, 2);
    sem = std(data, 0, 2) / sqrt(size(data, 2));
    errorbar(N_RANGE, mu, sem, 'Color', colors(i,:), 'LineWidth', 2, ...
        'LineStyle', line_styles{i}, 'Marker', markers{i}, 'MarkerFaceColor', 'w');
end
ylabel('Avg. Satisfaction (%)');
xlabel('Number of Users (N)');
title('(a) User Satisfaction (Higher is Better)');
legend(ALGORITHMS, 'Location', 'SouthWest', 'FontSize', 9);
ylim([0, 105]);

% 2. Latency
subplot(2, 2, 2); hold on; grid on;
for i = 1:length(ALGORITHMS)
    data = squeeze(results_scale.lat(:, i, :));
    mu = mean(data, 2);
    sem = std(data, 0, 2) / sqrt(size(data, 2));
    errorbar(N_RANGE, mu, sem, 'Color', colors(i,:), 'LineWidth', 2, ...
        'LineStyle', line_styles{i}, 'Marker', markers{i}, 'MarkerFaceColor', 'w');
end
ylabel('Avg. Latency (s)');
xlabel('Number of Users (N)');
title('(b) Average Latency (Lower is Better)');

% 3. Violation Rate
subplot(2, 2, 3); hold on; grid on;
for i = 1:length(ALGORITHMS)
    data = squeeze(results_scale.viol(:, i, :)) * 100; % Convert to %
    mu = mean(data, 2);
    plot(N_RANGE, mu, 'Color', colors(i,:), 'LineWidth', 2, ...
        'LineStyle', line_styles{i}, 'Marker', markers{i}, 'MarkerFaceColor', 'w');
end
ylabel('Violation Rate (%)');
xlabel('Number of Users (N)');
title('(c) Constraint Violation Rate');
ylim([-5, 105]);

% 4. Algorithm Runtime
subplot(2, 2, 4); hold on; grid on;
for i = 1:length(ALGORITHMS)
    data = squeeze(results_scale.time(:, i, :));
    mu = mean(data, 2);
    sem = std(data, 0, 2) / sqrt(size(data, 2));
    errorbar(N_RANGE, mu, sem, 'Color', colors(i,:), 'LineWidth', 2, ...
        'LineStyle', line_styles{i}, 'Marker', markers{i}, 'MarkerFaceColor', 'w');
end
ylabel('Avg. Runtime (s)');
xlabel('Number of Users (N)');
title('(d) Algorithm Runtime (Lower is Better)');
set(gca, 'YScale', 'log'); % Log scale for better visibility of GA vs Greedy

% Save
exportgraphics(h_fig1, fullfile(EXPORT_DIR, 'Fig_Overall_Performance.png'), 'Resolution', 300);
exportgraphics(h_fig1, fullfile(EXPORT_DIR, 'Fig_Overall_Performance.pdf'), 'ContentType', 'vector');
savefig(h_fig1, fullfile(EXPORT_DIR, 'Fig_Overall_Performance.fig'));

% --- Figure 3: Hardware-Profiled Satisfaction (N=50) ---
% Extract N=50 data from results_scale
n_50_idx = find(N_RANGE == 50);
if ~isempty(n_50_idx)
    h_fig3 = figure('Units', 'pixels', 'Position', [100, 100, 600, 400], 'Color', 'w');
    data_50 = squeeze(results_scale.sat(n_50_idx, :, :)); % [Algs, Runs]
    mu_50 = mean(data_50, 2);
    sem_50 = std(data_50, 0, 2) / sqrt(size(data_50, 2));
    
    b = bar(mu_50, 'FaceColor', 'flat');
    hold on;
    errorbar(1:length(ALGORITHMS), mu_50, sem_50, 'k', 'linestyle', 'none', 'LineWidth', 1.5);
    
    % Colors
    for i = 1:length(ALGORITHMS)
        b.CData(i,:) = colors(i,:);
    end
    
    set(gca, 'XTickLabel', ALGORITHMS, 'XTickLabelRotation', 45);
    ylabel('Avg. Satisfaction (%)');
    title('Hardware-Profiled Satisfaction (N=50)');
    ylim([0, 105]);
    grid on;
    
    exportgraphics(h_fig3, fullfile(EXPORT_DIR, 'Fig_Tier1_Satisfaction.png'), 'Resolution', 300);
    exportgraphics(h_fig3, fullfile(EXPORT_DIR, 'Fig_Tier1_Satisfaction.pdf'), 'ContentType', 'vector');
end

% --- Figure 4: Latency CDF (N=100) ---
fprintf('Generating CDF Data for N=100...\n');
[Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF] = generate_tier1_env_hetero(100, 5);
latencies_cdf = cell(length(ALGORITHMS), 1);
    
    % Store GA-Hybrid solution for injection
    cdf_hybrid_sol = [];

    for a_idx = 1:length(ALGORITHMS)
        alg_name = ALGORITHMS{a_idx};
        theta_bin = [];
        fprintf('Running algorithm: %s\n', alg_name);
        switch alg_name
            case 'Local', theta_bin = run_local(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF);
            case 'Cloud-Only', theta_bin = run_cloud(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF);
            case 'Greedy', theta_bin = Greedy_Solver_DNN(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF);
            case 'Neurosurgeon', theta_bin = Neurosurgeon_Solver(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF);
            case 'GA', theta_bin = GA_Solver_DNN_Vectorized(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF, 100, 100);
            case 'GA-Hybrid'
                theta_bin = GA_Hybrid_Solver(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF, struct('pop_size', 100, 'max_gen', 100));
                cdf_hybrid_sol = theta_bin;
            case 'Memetic-ALM'
                options_m = struct('pop_size', 100, 'max_gen', 100, 'alm_steps', 1000, ...
                                 'rho_start', 1e-4, 'rho_max', 10.0, 'rho_scale', 1.05, ...
                                 'elite_ratio', 0.1, 'alm_interval', 1);
                % Inject GA-Hybrid if available (Superset Strategy)
                if ~isempty(cdf_hybrid_sol)
                    options_m.initial_bin = cdf_hybrid_sol;
                    fprintf('  [Plot] Injecting GA-Hybrid seed into Memetic-ALM.\n');
                end
                theta_bin = Memetic_ALM_Solver(Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF, options_m);
        end
        
        [~, ~, ~, D_T, ~, ~] = calculate_metrics_v2(theta_bin, Task_CDF, Fog_CDF, Thing_CDF, DNN_Data_CDF);
        latencies_cdf{a_idx} = D_T;
    end

h_fig4 = figure('Units', 'pixels', 'Position', [100, 100, 600, 400], 'Color', 'w');
hold on; grid on;
for i = 1:length(ALGORITHMS)
    % Manual CDF plot to avoid toolbox dependency
    sorted_lat = sort(latencies_cdf{i});
    y_cdf = (1:length(sorted_lat)) / length(sorted_lat);
    plot(sorted_lat, y_cdf, 'LineWidth', 2, 'Color', colors(i,:), 'LineStyle', line_styles{i});
end
xlabel('Latency (s)');
ylabel('CDF');
title('Latency Distribution (N=100)');
legend(ALGORITHMS, 'Location', 'SouthEast');
xlim([0, 5]); % Focus on relevant range

exportgraphics(h_fig4, fullfile(EXPORT_DIR, 'Fig_Tier1_Latency_CDF.png'), 'Resolution', 300);
exportgraphics(h_fig4, fullfile(EXPORT_DIR, 'Fig_Tier1_Latency_CDF.pdf'), 'ContentType', 'vector');

% --- Figure 2: Ablation Study (if available) ---
if exist(fullfile(RESULTS_DIR, 'results_ablation_final.mat'), 'file')
    load(fullfile(RESULTS_DIR, 'results_ablation_final.mat')); % Load results_ablation, ABLATION_ALGS
    
    h_fig2 = figure('Units', 'pixels', 'Position', [100, 100, 600, 400], 'Color', 'w');
    data = results_ablation.sat; % [3, Runs]
    mu = mean(data, 2);
    sem = std(data, 0, 2) / sqrt(size(data, 2));
    
    b = bar(mu, 'FaceColor', 'flat');
    b.CData(1,:) = [0.93, 0.69, 0.13]; % GA
    b.CData(2,:) = [0.47, 0.67, 0.19] * 0.7; % Pure ALM (Darker Green)
    b.CData(3,:) = [0.47, 0.67, 0.19]; % Memetic ALM (Green)
    
    hold on;
    % Error Bars
    ngroups = size(data, 1);
    nbars = 1;
    groupwidth = min(0.8, nbars/(nbars + 1.5));
    x = (1:ngroups) - groupwidth/2 + (2*1-1) * groupwidth / (2*nbars);
    errorbar(x, mu, sem, 'k', 'linestyle', 'none', 'LineWidth', 1.5);
    
    set(gca, 'XTickLabel', ABLATION_ALGS, 'XTickLabelRotation', 0);
    ylabel('Avg. Satisfaction (%)');
    title('Ablation Study (N=100)');
    ylim([0, 105]);
    grid on;
    
    exportgraphics(h_fig2, fullfile(EXPORT_DIR, 'Fig_Ablation_Study.png'), 'Resolution', 300);
    exportgraphics(h_fig2, fullfile(EXPORT_DIR, 'Fig_Ablation_Study.pdf'), 'ContentType', 'vector');
end
