function [theta_bin, cost, viol_rate, time_taken, loss_history, theta_cont] = ALM_Solver_Wrapper(Task, Fog, Thing, DNN_Data, mu, rho_init, adam_iter, theta_init, beta_util)
    % ALM_SOLVER_WRAPPER: Memetic Augmented Lagrangian Solver Wrapper
    %
    % Wraps the current memetic ALM implementation used by the trace-driven
    % simulation pipeline.
    %
    % Features:
    % 1. Optional warm-start injection.
    % 2. Memetic population search with ALM local refinement.
    % 3. Post-evaluation through the shared feasibility-aware metric code.
    %
    
    if nargin < 9
        beta_util = 0.0;
    end
    
    if nargin < 7
        adam_iter = 500;
    end

    global task_num fog_num T;
    
    t_start = tic;
    fprintf('Running Memetic ALM Solver (Wrapper)...\n');
    
    % --- Initialization ---
    % Use neutral or random initialization if not provided.
    % We do NOT rely on Greedy for initialization to ensure algorithmic independence.
    theta_init_bin = [];
    if nargin >= 8 && ~isempty(theta_init)
        theta_init_bin = theta_init;
    end
    
    % --- Call Core Solver (HWS-ALM) ---
    % Pass parameters for the Entropy-Regularized solver
    core_options = struct();
    if ~isempty(theta_init_bin)
        core_options.theta_init_bin = theta_init_bin;
    end
    core_options.beta_util = beta_util;
    
    % Map to Advanced_Memetic_ALM options
    algo_options = struct();
    algo_options.max_gen = 20; % Fast run for visualization
    algo_options.pop_size = 30;
    algo_options.alm_steps = 10;
    
    % [theta_bin, loss_history, theta_logits] = ALM_Tier1_Core_V9_Crusher(Task, Fog, Thing, DNN_Data, adam_iter, core_options);
    % [theta_bin, loss_history, theta_logits] = ALM_Tier1_Core_V10_Ultimate(Task, Fog, Thing, DNN_Data, adam_iter, core_options);
    
    [theta_bin, ~, loss_history] = Advanced_Memetic_ALM(Task, Fog, Thing, DNN_Data, algo_options);
    theta_logits = double(theta_bin); % Proxy for logits
    
    % --- Post-Processing & Verification ---
    % Check for Violations
    [avg_satis, ~, ~, viol_rate] = evaluate_solution(theta_bin, Task, Fog, Thing, DNN_Data, 0.01, false, 0);
    cost = (100 - avg_satis) + (viol_rate * 10000);
    
    % Return formatted results
    % theta_cont is now theta_logits (useful for analysis)
    theta_cont = theta_logits(:);
    
    time_taken = toc(t_start);
end
