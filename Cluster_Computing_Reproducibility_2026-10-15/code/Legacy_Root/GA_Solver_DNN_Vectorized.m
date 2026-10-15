function [best_theta, best_fitness, loss_history] = GA_Solver_DNN_Vectorized(Task, Fog, Thing, DNN_Data, pop_size, max_gen)
    % GA_SOLVER_DNN_VECTORIZED
    % High-Performance Genetic Algorithm for Tier-1 Baseline.
    % Fully vectorized evaluation to support Pop=100+, Gen=200+.
    
    global task_num fog_num T;
    
    if nargin < 5, pop_size = 100; end
    if nargin < 6, max_gen = 200; end
    
    % --- Ensure Dimensions are Valid ---
    if isempty(task_num) || isempty(fog_num) || isempty(T)
        task_num = size(Task, 1);
        fog_num = size(Fog, 1);
        if iscell(DNN_Data)
            T = length(DNN_Data{1}.comp);
        else
            T = length(DNN_Data.comp);
        end
    end
    % Force update from input (Robustness)
    task_num = size(Task, 1);
    fog_num = size(Fog, 1);
    
    fprintf('  [GA-Vec] Starting GA (Pop=%d, Gen=%d)...\n', pop_size, max_gen);
    
    % Chromosome: Binary vector of length N*T*F
    chrom_len = task_num * T * fog_num;
    
    % 1. Initialization
    pop = randi([0, 1], pop_size, chrom_len);
    pop = repair_population(pop, task_num, T, fog_num);
    
    % --- Standard GA uses Random Initialization ---
    % Greedy Initialization is reserved for Hybrid/Memetic algorithms (P-ALM).
    % This ensures a fair comparison between "Pure Evolutionary" and "Physics-Aware Hybrid" methods.
    % (Commented out Greedy Injection for Baseline Purity)
    %{
    try
        theta_greedy = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data);
        pop(1, :) = theta_greedy(:)';
    catch
    end
    for j = 2:min(5, pop_size)
        mask = rand(1, chrom_len) < (5.0 / chrom_len);
        pop(j, :) = repair_population(xor(pop(1, :), mask), task_num, T, fog_num);
    end
    %}
    
    % Pre-compute Constants
    % Use Tier1 builder for consistency and robustness
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    best_fitness = -inf;
    best_theta = zeros(chrom_len, 1);
    loss_history = zeros(1, max_gen);
    
    base_mut_rate = 1.0 / chrom_len;
    
    % 2. Evolution Loop
    for gen = 1:max_gen
        % A. Batch Evaluation
        [fitness, avg_sat, viol_rate] = calculate_metrics_batch(pop, Pre, Fog, Task, Thing);
        
        % Record Best
        [max_f, idx] = max(fitness);
        if max_f > best_fitness
            best_fitness = max_f;
            best_theta = pop(idx, :)';
        end
        
        % Loss for plotting (Negative Fitness)
        loss_history(gen) = -best_fitness;
        
        % B. Selection (Tournament)
        % Vectorized Tournament
        tour_size = 5;
        % Random candidates: [PopSize, TourSize]
        candidates_idx = randi(pop_size, pop_size, tour_size);
        candidates_fit = fitness(candidates_idx); % [PopSize, TourSize]
        [~, best_cand_local_idx] = max(candidates_fit, [], 2);
        
        % Linear index to get parent indices
        % idx_in_candidates = sub2ind([pop_size, tour_size], (1:pop_size)', best_cand_local_idx);
        % parent_indices = candidates_idx(idx_in_candidates);
        
        % Simplified: Just get the parent indices directly
        parent_indices = zeros(pop_size, 1);
        for i=1:pop_size
            parent_indices(i) = candidates_idx(i, best_cand_local_idx(i));
        end
        
        parents = pop(parent_indices, :);
        
        % C. Crossover (Single Point) - Vectorized
        % Shuffle parents to form pairs
        p1 = parents(1:2:end, :);
        p2 = parents(2:2:end, :);
        
        % If odd pop_size, handle last one (just keep it)
        if mod(pop_size, 2) ~= 0
             p1 = [p1; parents(end, :)];
             p2 = [p2; parents(1, :)]; % Wrap around
        end
        
        n_pairs = size(p1, 1);
        pts = randi(chrom_len-1, n_pairs, 1);
        
        % Mask creation is tricky vectorized.
        % Iterate is faster than creating massive mask matrix.
        children = zeros(size(pop));
        for i=1:n_pairs
            pt = pts(i);
            children(2*i-1, :) = [p1(i, 1:pt), p2(i, pt+1:end)];
            children(2*i, :)   = [p2(i, 1:pt), p1(i, pt+1:end)];
        end
        
        if mod(pop_size, 2) ~= 0
            children = children(1:pop_size, :);
        end
        
        % D. Mutation (Bit Flip) - Vectorized
        mut_mask = rand(pop_size, chrom_len) < base_mut_rate;
        pop = xor(children, mut_mask);
        pop = repair_population(pop, task_num, T, fog_num);
        
        % Elitism: Restore best
        pop(1, :) = best_theta';
        
        if mod(gen, 50) == 0
             % fprintf('    Gen %d: Best Fit=%.2f (Sat=%.2f%%)\n', gen, best_fitness, max(avg_sat));
        end
    end
end
function pop_fixed = repair_population(pop, N, T, F)
    [M, L] = size(pop);
    Z = reshape(pop, [M * N * T, F]);
    s = sum(Z, 2);
    R = rand(size(Z));
    Y = Z + R .* Z;
    [~, arg] = max(Y, [], 2);
    Z_new = zeros(size(Z));
    rows = find(s >= 1);
    if ~isempty(rows)
        idx = sub2ind([M * N * T, F], rows, arg(rows));
        Z_new(idx) = 1;
    end
    pop_fixed = reshape(Z_new, [M, L]);
end
