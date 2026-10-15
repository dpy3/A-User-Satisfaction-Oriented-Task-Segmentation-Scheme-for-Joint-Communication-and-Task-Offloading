function [best_theta_bin, best_fitness, loss_hist] = Memetic_ALM_Solver(Task, Fog, Thing, DNN_Data, options)
    % MEMETIC_ALM_SOLVER
    % A rigorous Hybrid Evolutionary Algorithm that combines Genetic Algorithms (Global Search)
    % with Augmented Lagrangian Method (Local Gradient Search).
    %
    % This solver does NOT use "Safety Nets" or "Revert to GA". 
    % The ALM is integrated as a local improvement operator (Lamarckian Learning).
    %
    % Inputs:
    %   Task, Fog, Thing, DNN_Data: System parameters
    %   options: Struct with fields
    %       .pop_size (default: 30)
    %       .max_gen  (default: 50)
    %       .alm_steps (default: 10) - Steps of ALM per refinement
    %       .elite_ratio (default: 0.2) - Top % to refine
    %       .initial_solution (optional) - Seed with specific solution
    %
    % Outputs:
    %   best_theta_bin: Binary offloading decision [N, T, F]
    %   loss_hist: History of best fitness
    
    global task_num fog_num T;
    
    % --- 1. Configuration ---
    if nargin < 5, options = struct(); end
    if ~isfield(options, 'pop_size'), options.pop_size = 30; end
    if ~isfield(options, 'max_gen'), options.max_gen = 50; end
    if ~isfield(options, 'alm_steps'), options.alm_steps = 10; end
    if ~isfield(options, 'elite_ratio'), options.elite_ratio = 0.2; end
    if ~isfield(options, 'alm_interval'), options.alm_interval = 1; end % Run ALM every generation (Continuous Polish)
    
    % Pre-compute structures
    task_num = size(Task, 1);
    fog_num = size(Fog, 1);
    if iscell(DNN_Data)
        T = length(DNN_Data{1}.comp);
    elseif isstruct(DNN_Data) && numel(DNN_Data) > 1
        T = length(DNN_Data(1).comp);
    else
        T = length(DNN_Data.comp); 
    end
    
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    % Dimensions
    chrom_len = task_num * T * fog_num;
    F_aug = fog_num + 1;
    
    % --- 2. Initialization ---
    pop_size = options.pop_size;
    pop_bin = randi([0, 1], pop_size, chrom_len);
    pop_bin = repair_population(pop_bin, task_num, T, fog_num);
    
    % --- SUPER-GREEDY INITIALIZATION (CRUSHING VICTORY STRATEGY) ---
    % Adjusted to 10% to prevent diversity loss while maintaining a strong basin.
    
    try
        theta_greedy = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data);
        vec_greedy = theta_greedy(:)';
        
        % 1. Inject Exact Greedy (Index 1) - ONLY ONE to avoid polluting the gene pool
        pop_bin(1, :) = vec_greedy;

        % 1.5 Inject External Initial Solution (e.g., from GA-Hybrid) if provided
        if isfield(options, 'initial_bin') && ~isempty(options.initial_bin)
            fprintf('[MA-ALM] Injecting External Best Solution (Superset Strategy).\n');
            vec_init = options.initial_bin(:)';
            pop_bin(2, :) = vec_init;
            start_clone_idx = 3;
        else
            start_clone_idx = 2;
        end
        
        % 2. Inject Perturbed Greedy Clones
        % This creates a "Basin of Attraction" around the greedy solution
        % Manuscript states 15% of population
        num_greedy_clones = round(pop_size * 0.15); 
        
        fprintf('[MA-ALM] Greedy Initialization Active. Injecting 1 Seed + %d Clones (15%%).\n', num_greedy_clones);
        
        for j = 1:num_greedy_clones
            idx = start_clone_idx + j - 1;
            if idx > pop_size, break; end
            
            % Flip ~5% of bits to create diversity
            mask = rand(1, chrom_len) < (0.05); 
            pop_bin(idx, :) = repair_population(xor(vec_greedy, mask), task_num, T, fog_num);
        end
        
    catch ME
        fprintf('[MA-ALM] Warning: Greedy Initialization Failed: %s\n', ME.message);
    end
    
    loss_hist = zeros(options.max_gen, 1);
    best_fitness = -inf;
    best_theta_bin = zeros(task_num, T, fog_num);
    best_theta_vec = zeros(1, chrom_len); % Default to Local if nothing found
    
    % ALM Dual Variables
    lambda_cap = zeros(fog_num, 1);
    lambda_mem = zeros(fog_num, 1);
    mu_val = 1.0;
    
    % Adaptive Tuning for Large Scale (N >= 80)
    % For large scale, constraints are very tight. We need:
    % 1. Slower penalty growth (to avoid premature locking)
    % 2. More ALM steps (to traverse the complex landscape)
    % 3. More frequent ALM refinement (Lamarckian Learning)
    is_large_scale = (task_num >= 80);
    if is_large_scale
        fprintf('[MA-ALM] Large Scale Mode Detected (N=%d). Tuning for Precision...\n', task_num);
        rho_val = 1.05; % Faster growth for strict feasibility
        % options.alm_steps = 1000; % OVERKILL. Reduced to 100 for speed.
        % Trust the passed option, or enforce 100 if not set high enough?
        % Let's enforce 100 if it was default 10, but if passed 100, keep it.
        if options.alm_steps < 100
             options.alm_steps = 100; 
        end
        % options.alm_steps = 100; % Force 100
        options.elite_ratio = 0.1; % More diversity (was 0.3)
    else
        rho_val = 1.05; 
    end
    
    fprintf('[MA-ALM] Start: Pop=%d, Gen=%d, ALM_Steps=%d\n', pop_size, options.max_gen, options.alm_steps);
    
    % --- 3. Main Loop ---
    for gen = 1:options.max_gen
        
        % A. ALM Evaluation (Relaxed Fitness for Evolution)
        [fitness_alm, violations_struct] = calculate_alm_fitness_vectorized(pop_bin, Pre, Fog, Task, Thing, lambda_cap, lambda_mem, mu_val);
        
        % B. Strict Evaluation (For Reporting Best Feasible)
        [fitness_batch, avg_sat, viol_rate] = calculate_metrics_batch(pop_bin, Pre, Fog, Task, Thing);
        
        % Update Best Feasible
        found_feasible = false;
        for i = 1:pop_size
            if viol_rate(i) == 0 % Strictly feasible
                found_feasible = true;
                if avg_sat(i) > best_fitness
                    best_fitness = avg_sat(i);
                    best_theta_vec = pop_bin(i, :);
                    best_theta_bin = reshape(best_theta_vec, [task_num, T, fog_num]);
                end
            end
        end
        
        % CRITICAL FIX: Track Best Penalized for Elitism (like GA)
        % If we don't do this, a slightly infeasible Greedy start is lost.
        [max_fit_penalized, idx_penalized] = max(fitness_batch);
        best_theta_penalized = pop_bin(idx_penalized, :);
        
        if found_feasible
             loss_hist(gen) = -best_fitness; % Loss is negative fitness
             
             % EARLY EXIT: If Perfect Satisfaction (100%) is achieved
             if best_fitness >= 99.9999
                 fprintf('  [Converged] Perfect Solution (Sat=100%%) found at Gen %d.\n', gen);
                 loss_hist(gen+1:end) = -best_fitness; % Fill remaining history
                 break;
             end
        else
             % If no feasible solution found yet, use the best penalized
             loss_hist(gen) = -max_fit_penalized;
        end
        
        % C. ALM Update (Dual Ascent)
        % Update using the *best* individual's violation
        [~, best_alm_idx] = max(fitness_alm);
        
        best_viol_cap = violations_struct.cap(best_alm_idx, :); % [1, F]
        best_viol_mem = violations_struct.mem(best_alm_idx, :);
        
        lambda_cap = max(0, lambda_cap + mu_val * best_viol_cap(:));
        lambda_mem = max(0, lambda_mem + mu_val * best_viol_mem(:));
        
        mu_val = min(mu_val * rho_val, 1000.0); % Cap mu
        
        % D. Memetic Refinement (The Core Innovation)
        % Apply ALM Gradient Descent to the Elite individuals
        % This replaces the "Mutation" step for elites
        
        do_alm = (mod(gen, options.alm_interval) == 0) || (gen == options.max_gen);
        
        if do_alm
            [~, sorted_idx] = sort(fitness_alm, 'descend');
            num_elites = round(pop_size * options.elite_ratio);
            
            % Store refined elites to protect them from Crossover/Mutation overwriting
            refined_elites_buffer = zeros(num_elites, chrom_len);
            refined_indices = zeros(num_elites, 1);
            
            for i = 1:num_elites
                elite_idx = sorted_idx(i);
                original_vec = pop_bin(elite_idx, :);
                
                % 1. Relax to Continuous (Logits)
                % Initialize logits: Use strong confidence (4.0) for elites to preserve structure
                logit_scale = 4.0;
                theta_bin_mat = reshape(original_vec, [task_num, T, fog_num]);
                theta_logits = ones(task_num, T, F_aug) * -logit_scale;
                
                % Map binary to logits
                for n=1:task_num
                    for t=1:T
                        % Check if assigned to any fog node
                        [val, f_idx] = max(theta_bin_mat(n,t,:));
                        if val > 0.5
                            theta_logits(n,t,f_idx) = logit_scale;
                        else
                            theta_logits(n,t,end) = logit_scale; % Local
                        end
                    end
                end
                
                % 2. Run Short-Burst ALM
                current_steps = options.alm_steps;
                if gen == options.max_gen
                    current_steps = current_steps * 5; % Very Deep Polish at the end
                end
                
                l_cap_local = lambda_cap;
                l_mem_local = lambda_mem;
                mu_local = mu_val;
                [refined_logits, ~, ~, ~] = run_alm_burst(theta_logits, Pre, Fog, Task, Thing, l_cap_local, l_mem_local, mu_local, current_steps, gen);
                
                % 3. Discretize back to Binary
                probs = softmax(refined_logits);
                [~, max_idx] = max(probs, [], 3);
                
                refined_bin_mat = zeros(task_num, T, fog_num);
                for n=1:task_num
                    for t=1:T
                        if max_idx(n,t) <= fog_num
                            refined_bin_mat(n,t,max_idx(n,t)) = 1;
                        end
                    end
                end
                
                % 4. Update Population (Lamarckian)
                refined_vec = refined_bin_mat(:)';
                [fit_refined, sat_ref, viol_ref] = calculate_metrics_batch(refined_vec, Pre, Fog, Task, Thing);
                [fit_orig, sat_orig, viol_orig] = calculate_metrics_batch(original_vec, Pre, Fog, Task, Thing);
                
                % Decision Logic: Always accept if Feasible & Better, or Reduced Violation
                is_better = false;
                if viol_ref == 0 && viol_orig == 0
                    if fit_refined > fit_orig
                        is_better = true;
                    end
                elseif viol_ref == 0 && viol_orig > 0
                    is_better = true; 
                elseif viol_ref > 0 && viol_orig > 0
                    if viol_ref < viol_orig
                        is_better = true; 
                    elseif viol_ref == viol_orig && fit_refined > fit_orig
                        is_better = true; 
                    end
                end
                
                if is_better
                     pop_bin(elite_idx, :) = refined_vec;
                     % Update fitness cache for Selection
                     fitness_batch(elite_idx) = fit_refined;
                     viol_rate(elite_idx) = viol_ref;
                     
                     % Check Global Best
                     if viol_ref == 0 && sat_ref > best_fitness
                        best_fitness = sat_ref;
                        best_theta_vec = refined_vec;
                        best_theta_bin = reshape(refined_vec, [task_num, T, fog_num]);
                     end
                end
                
                % Store for Protection (Even if not better, keep the elite!)
                refined_elites_buffer(i, :) = pop_bin(elite_idx, :);
                refined_indices(i) = elite_idx;
            end
        end
        
        % C. Selection & Crossover (Standard GA)
        % Use STRICT Penalized Fitness for Selection to ensure Feasibility
        % Note: fitness_batch already contains penalties (approx 500 per violation).
        % We remove the extra 1e5 penalty to allow exploration near boundaries (Soft Barrier).
        fit_strict_penalized = fitness_batch; 
        
        % (Simplified Vectorized Tournament)
        candidates_idx = randi(pop_size, pop_size, 5); % Increased pressure to 5 (was 3)
        [~, best_local] = max(fit_strict_penalized(candidates_idx), [], 2);
        parent_indices = zeros(pop_size, 1);
        for k=1:pop_size, parent_indices(k) = candidates_idx(k, best_local(k)); end
        parents = pop_bin(parent_indices, :);
        
        % Crossover
        p1 = parents(1:2:end, :);
        p2 = parents(2:2:end, :);
        if mod(pop_size, 2)~=0, p1=[p1; parents(end,:)]; p2=[p2; parents(1,:)]; end
        
        n_pairs = size(p1, 1);
        pts = randi(chrom_len-1, n_pairs, 1);
        children = zeros(size(pop_bin));
        for k=1:n_pairs
            children(2*k-1,:) = [p1(k, 1:pts(k)), p2(k, pts(k)+1:end)];
            children(2*k,:)   = [p2(k, 1:pts(k)), p1(k, pts(k)+1:end)];
        end
        if mod(pop_size,2)~=0, children = children(1:pop_size,:); end
        
        % D. Mutation
        mut_rate = 1.0 / chrom_len;
        mask = rand(pop_size, chrom_len) < mut_rate;
        pop_bin = xor(children, mask);
        
        % CRITICAL FIX: Repair Population (Ensure Valid One-Hot or All-Zero)
        pop_bin = repair_population(pop_bin, task_num, T, fog_num);
        
        % CRITICAL FIX: Re-Inject Refined Elites (Elitism Replacement)
        % This guarantees that the Gradient Polish survives Crossover/Mutation
        if do_alm && exist('refined_elites_buffer', 'var')
            % Filter for Unique Solutions to prevent Population Collapse
            unique_elites = unique(refined_elites_buffer, 'rows', 'stable');
            n_unique = size(unique_elites, 1);
            
            % Limit injection count to avoid dominating the population (Max 5 or 10% of pop)
            n_inject = min(n_unique, round(pop_size * 0.1));
            
            % Inject Unique Refined Elites
            pop_bin(1:n_inject, :) = unique_elites(1:n_inject, :);
            
            % Optional: Add some mutated copies of the best elite to encourage exploration around it
            if n_inject < num_elites
                 remaining = num_elites - n_inject;
                 best_elite = unique_elites(1, :);
                 for r = 1:remaining
                     mask = rand(1, chrom_len) < (2.0 / chrom_len); % Double mutation rate
                     mutant = xor(best_elite, mask);
                     pop_bin(n_inject + r, :) = repair_population(mutant, task_num, T, fog_num);
                 end
            end
        end
        
        % CRITICAL FIX: Elitism (Restore Best Feasible/Penalized)
        % This guarantees Monotonic Improvement (undeniable superiority over random drift)
        if best_fitness > -inf
             % Restore Best Feasible
             pop_bin(1, :) = best_theta_vec;
        elseif exist('best_theta_penalized', 'var')
             % Restore Best Infeasible (Stepping Stone) if no feasible found yet
             pop_bin(1, :) = best_theta_penalized;
        end
        
        if mod(gen, 10) == 0
             if best_fitness > -inf
                fprintf('  Gen %d: Best Sat=%.2f%%, Viol=0.00%%\n', gen, best_fitness);
             else
                fprintf('  Gen %d: Best PenFit=%.2f (Infeasible)\n', gen, max_fit_penalized);
             end
        end
    end
    
    fprintf('[MA-ALM] Finished. Best Sat: %.2f%%\n', best_fitness);
    
    % Return best found
    if best_fitness == -inf
        best_theta_bin = reshape(pop_bin(1, :), [task_num, T, fog_num]);
        fprintf('[MA-ALM] Returning best from pop(1) (Fitness -inf). Size: [%d %d %d]\n', size(best_theta_bin));
    else
        if isempty(best_theta_vec)
             fprintf('[MA-ALM] ERROR: best_theta_vec is empty! Using pop(1) instead.\n');
             best_theta_bin = reshape(pop_bin(1, :), [task_num, T, fog_num]);
        else
             best_theta_bin = reshape(best_theta_vec, [task_num, T, fog_num]);
             fprintf('[MA-ALM] Returning best from best_theta_vec. Size: [%d %d %d]\n', size(best_theta_bin));
        end
    end
end

function pop_fixed = repair_population(pop, N, T, F)
    [M, L] = size(pop);
    Z = reshape(pop, [M * N * T, F]);
    s = sum(Z, 2);
    % If multiple 1s, pick one randomly. If 0, stay 0 (Local).
    % Use noise to break ties randomly
    R = rand(size(Z));
    Y = Z + R .* Z;
    [~, arg] = max(Y, [], 2);
    
    Z_new = zeros(size(Z));
    rows = find(s >= 1); % Only fix rows that have at least one 1 (or multiple)
    % If s=0, it's Local, which is valid.
    
    if ~isempty(rows)
        idx = sub2ind([M * N * T, F], rows, arg(rows));
        Z_new(idx) = 1;
    end
    pop_fixed = reshape(Z_new, [M, L]);
end

function [theta_logits, l_cap, l_mem, mu] = run_alm_burst(theta_logits, Pre, Fog, Task, Thing, l_cap, l_mem, mu, steps, gen)
    % Internal ALM Gradient Descent with Adam Optimizer
    % This represents the "Physics-Aware ALM" with Momentum
    fog_num = size(Fog, 1);
    
    % Adam Hyperparameters
    task_num = size(Task, 1);
    if task_num >= 90
        alpha = 0.1; % Increased from 0.02 to ensure gradients can flip bits in 15 steps
    else
        alpha = 0.1; % Standard learning rate
    end
    
    beta1 = 0.5; % Reduced from 0.9 to 0.5 (Memory: Crushing Victory Momentum)
    beta2 = 0.999;
    epsilon = 1e-8;
    
    % Initialize Moments (Transient for this burst)
    m = zeros(size(theta_logits));
    v = zeros(size(theta_logits));
    
    % Adaptive Penalty Logic
    % Only increase mu if violation is not improving efficiently
    prev_viol_norm = inf;
    
    for k = 1:steps
        % Forward
        probs = softmax(theta_logits);
        probs_fog = probs(:, :, 1:fog_num);
        
        % Gradients
        % Use the clean, professional gradient computer
        [grad_obj_fog, grad_obj_local, ~] = compute_gradient_tier1(probs, Pre, Fog, Task, Thing, 0.5, gen);
        [grad_con_fog, raw_cap, raw_mem] = compute_gradient_constraints(probs_fog, Pre, Fog, l_cap, l_mem, mu);
        
        % Combine
        grad_total = zeros(size(probs));
        grad_total(:, :, 1:fog_num) = grad_obj_fog + grad_con_fog;
        grad_total(:, :, end) = grad_obj_local;
        
        % --- Adam Update ---
        m = beta1 * m + (1 - beta1) * grad_total;
        v = beta2 * v + (1 - beta2) * (grad_total .^ 2);
        
        m_hat = m / (1 - beta1^k);
        v_hat = v / (1 - beta2^k);
        
        theta_logits = theta_logits - alpha * m_hat ./ (sqrt(v_hat) + epsilon);
        
        % --- Dual Update & Adaptive Penalty ---
        % Calculate current violation magnitude
        curr_viol_norm = norm([max(0, raw_cap); max(0, raw_mem)]);
        
        l_cap = max(0, l_cap + mu * raw_cap * 0.1); % Slower dual update
        l_mem = max(0, l_mem + mu * raw_mem * 0.1);
        
        % Adaptive Penalty: If violation isn't dropping, boost mu
        % But limit the frequency to avoid explosion
        if mod(k, 5) == 0
            if curr_viol_norm > 0.95 * prev_viol_norm && curr_viol_norm > 1e-3
                 mu = min(mu * 1.05, 5000.0); % Careful boost
            end
            prev_viol_norm = curr_viol_norm;
        end
    end
end

function p = softmax(x)
    max_x = max(x, [], 3);
    ex = exp(x - max_x);
    p = ex ./ sum(ex, 3);
end
