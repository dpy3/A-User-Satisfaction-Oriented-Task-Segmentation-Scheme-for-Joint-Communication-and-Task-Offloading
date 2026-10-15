% RUN_FINAL_BATCH_1
% Runs 1-15 of the Manuscript Experiments
clc; clear; close all;
diary('crash_log_batch1.txt');
diary on;

RESULTS_DIR = 'Results_Final_Publication';
if ~exist(RESULTS_DIR, 'dir'), mkdir(RESULTS_DIR); end

START_RUN = 1;
END_RUN = 15;
FOG_NUM = 5;
N_RANGE = [30, 50, 70, 80, 90, 100];
ALGORITHMS = {'Local', 'Greedy', 'GA', 'GA-Hybrid', 'Memetic-ALM'};

% --- Experiment 1 ---
fprintf('=== Batch 1: Exp 1 Scalability (Runs %d-%d) ===\n', START_RUN, END_RUN);

results_scale = struct();
% Initialize full size to match structure, but we only fill 1-15
results_scale.sat = zeros(length(N_RANGE), length(ALGORITHMS), 30);
results_scale.lat = zeros(length(N_RANGE), length(ALGORITHMS), 30);
results_scale.viol = zeros(length(N_RANGE), length(ALGORITHMS), 30);
results_scale.time = zeros(length(N_RANGE), length(ALGORITHMS), 30);

checkpoint_file = fullfile(RESULTS_DIR, 'results_batch_1_checkpoint.mat');
if exist(checkpoint_file, 'file')
    load(checkpoint_file);
    fprintf('Resuming Batch 1...\n');
end

for n_idx = 1:length(N_RANGE)
    n_users = N_RANGE(n_idx);
    fprintf('  Running N = %d ...\n', n_users);
    
    for r = START_RUN:END_RUN
        fprintf('    Run %d/15...\n', r);
        
        try
            [Task, Fog, Thing, DNN_Data] = generate_tier1_env_hetero(n_users, FOG_NUM);
            best_baseline_bin = [];
            
            for a_idx = 1:length(ALGORITHMS)
                alg_name = ALGORITHMS{a_idx};
                
                % SKIP if done
                if results_scale.sat(n_idx, a_idx, r) ~= 0 && ...
                   ~strcmp(alg_name, 'GA-Hybrid') && ...
                   ~strcmp(alg_name, 'Memetic-ALM')
                    continue;
                end
                
                t_start = tic;
                theta_bin = [];
                switch alg_name
                    case 'Local', theta_bin = run_local(Task, Fog, Thing, DNN_Data);
                    case 'Greedy', theta_bin = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data);
                    case 'GA'
                        options_ga = struct('pop_size', 100, 'max_gen', 100);
                        theta_bin = GA_Solver_DNN_Vectorized(Task, Fog, Thing, DNN_Data, 100, 100);
                    case 'GA-Hybrid'
                        options_ga = struct('pop_size', 100, 'max_gen', 100);
                        theta_bin = GA_Hybrid_Solver(Task, Fog, Thing, DNN_Data, options_ga);
                        best_baseline_bin = theta_bin;
                    case 'Memetic-ALM'
                        options_alm = struct('pop_size', 100, 'max_gen', 100, 'alm_steps', 1000, ...
                                           'rho_start', 1e-4, 'rho_max', 10.0, 'rho_scale', 1.05, ...
                                           'elite_ratio', 0.1, 'alm_interval', 1);
                        if ~isempty(best_baseline_bin)
                             options_alm.initial_bin = best_baseline_bin;
                        end
                        theta_bin = Memetic_ALM_Solver(Task, Fog, Thing, DNN_Data, options_alm);
                end
                t_end = toc(t_start);
                
                [sat, lat, ~, viol] = evaluate_solution(theta_bin, Task, Fog, Thing, DNN_Data);
                results_scale.sat(n_idx, a_idx, r) = sat;
                results_scale.viol(n_idx, a_idx, r) = viol;
                results_scale.lat(n_idx, a_idx, r) = lat;
                results_scale.time(n_idx, a_idx, r) = t_end;
                
                fprintf('      [%s] Sat=%.2f%%, Viol=%.2f%%\n', alg_name, sat, viol*100);
            end
        catch ME
            fprintf('Error: %s\n', ME.message);
        end
    end
    save(checkpoint_file, 'results_scale', 'N_RANGE', 'ALGORITHMS');
end
save(fullfile(RESULTS_DIR, 'results_batch_1.mat'), 'results_scale', 'N_RANGE', 'ALGORITHMS');

% --- Experiment 3 (Ablation) ---
fprintf('=== Batch 1: Exp 3 Ablation (Runs %d-%d) ===\n', START_RUN, END_RUN);
ABLATION_ALGS = {'Pure-GA', 'Pure-ALM', 'Memetic-ALM'};
results_ablation = struct();
results_ablation.sat = zeros(length(ABLATION_ALGS), 30);
results_ablation.viol = zeros(length(ABLATION_ALGS), 30);

ablation_checkpoint = fullfile(RESULTS_DIR, 'ablation_batch_1_checkpoint.mat');
if exist(ablation_checkpoint, 'file'), load(ablation_checkpoint); end

for r = START_RUN:END_RUN
    fprintf('    Run %d/15...\n', r);
    [Task, Fog, Thing, DNN_Data] = generate_tier1_env_hetero(100, FOG_NUM);
    
    % Pure GA
    if results_ablation.sat(1, r) == 0
        theta = GA_Solver_DNN_Vectorized(Task, Fog, Thing, DNN_Data, 100, 100);
        [s, v, ~] = calculate_metrics_v2(theta, Task, Fog, Thing, DNN_Data);
        results_ablation.sat(1, r) = s; results_ablation.viol(1, r) = v;
    end
    
    % Pure ALM
    if results_ablation.sat(2, r) == 0
        theta = Pure_ALM_Solver(Task, Fog, Thing, DNN_Data, 100);
        [s, v, ~] = calculate_metrics_v2(theta, Task, Fog, Thing, DNN_Data);
        results_ablation.sat(2, r) = s; results_ablation.viol(2, r) = v;
    end
    
    % Memetic
    if results_ablation.sat(3, r) == 0
        opts = struct('pop_size', 100, 'max_gen', 100, 'alm_steps', 30, 'elite_ratio', 0.2, 'alm_interval', 5);
        theta = Memetic_ALM_Solver(Task, Fog, Thing, DNN_Data, opts);
        [s, v, ~] = calculate_metrics_v2(theta, Task, Fog, Thing, DNN_Data);
        results_ablation.sat(3, r) = s; results_ablation.viol(3, r) = v;
    end
    save(ablation_checkpoint, 'results_ablation', 'ABLATION_ALGS');
end
save(fullfile(RESULTS_DIR, 'ablation_batch_1.mat'), 'results_ablation', 'ABLATION_ALGS');
