function [best_theta, best_fitness, loss_history] = GA_Hybrid_Solver(Task, Fog, Thing, DNN_Data, options)
    % GA_HYBRID_SOLVER
    % A "Strong Baseline" Genetic Algorithm that uses Greedy Initialization.
    % This is used to prove that P-ALM's victory is not just due to initialization,
    % but due to the Physics-Aware Gradient Descent.
    
    global task_num fog_num T;
    
    % --- Handle Input Arguments ---
    pop_size = 100;
    max_gen = 200;
    
    if nargin >= 5
        if isstruct(options)
            if isfield(options, 'pop_size'), pop_size = options.pop_size; end
            if isfield(options, 'max_gen'), max_gen = options.max_gen; end
        elseif isnumeric(options)
            pop_size = options;
            if nargin >= 6
                % Handle legacy call: GA_Hybrid_Solver(..., pop_size, max_gen)
                % Not standard but defensive
                % We can't access varargin here easily without changing signature
                % But based on signature change to 'options', we assume struct usage mainly.
            end
        end
    end
    
    % Support legacy 6-arg call via varargin if needed, but for now let's just support struct
    % Or better, keep signature flexible:
    % function ... = GA_Hybrid_Solver(Task, Fog, Thing, DNN_Data, arg5, arg6)
    
    % Let's stick to the file modification with flexible parsing

    
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
    task_num = size(Task, 1);
    fog_num = size(Fog, 1);
    
    fprintf('  [GA-Hybrid] Starting Hybrid GA (Pop=%d, Gen=%d)...\n', pop_size, max_gen);
    
    % Chromosome: Binary vector of length N*T*F
    chrom_len = task_num * T * fog_num;
    
    % 1. Initialization
    pop = randi([0, 1], pop_size, chrom_len);
    pop = repair_population(pop, task_num, T, fog_num);
    
    % --- HYBRID INITIALIZATION (Strong Baseline) ---
    % Inject Greedy solution and perturbed clones
    try
        theta_greedy = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data);
        vec_greedy = theta_greedy(:)';
        
        % Inject 1 Exact Greedy
        pop(1, :) = vec_greedy;
        
        % Inject 15% Perturbed Clones (Matching P-ALM's setup)
        num_clones = round(pop_size * 0.15);
        for j = 1:num_clones
            idx = 1 + j;
            if idx > pop_size, break; end
            
            % Flip ~5% of bits
            mask = rand(1, chrom_len) < 0.05;
            pop(idx, :) = repair_population(xor(vec_greedy, mask), task_num, T, fog_num);
        end
        fprintf('  [GA-Hybrid] Injected Greedy + %d Clones.\n', num_clones);
    catch ME
        fprintf('  [GA-Hybrid] Warning: Greedy Init Failed: %s\n', ME.message);
    end
    
    % Pre-compute Constants
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
        
        loss_history(gen) = -best_fitness;
        
        % B. Selection (Tournament)
        tour_size = 5;
        candidates_idx = randi(pop_size, pop_size, tour_size);
        candidates_fit = fitness(candidates_idx);
        [~, best_cand_local_idx] = max(candidates_fit, [], 2);
        
        parent_indices = zeros(pop_size, 1);
        for i=1:pop_size
            parent_indices(i) = candidates_idx(i, best_cand_local_idx(i));
        end
        parents = pop(parent_indices, :);
        
        % C. Crossover (Single Point)
        p1 = parents(1:2:end, :);
        p2 = parents(2:2:end, :);
        
        if mod(pop_size, 2) ~= 0
             p1 = [p1; parents(end, :)];
             p2 = [p2; parents(1, :)];
        end
        
        n_pairs = size(p1, 1);
        pts = randi(chrom_len-1, n_pairs, 1);
        
        children = zeros(size(pop));
        for i=1:n_pairs
            pt = pts(i);
            children(2*i-1, :) = [p1(i, 1:pt), p2(i, pt+1:end)];
            children(2*i, :)   = [p2(i, 1:pt), p1(i, pt+1:end)];
        end
        
        if mod(pop_size, 2) ~= 0
            children = children(1:pop_size, :);
        end
        
        % D. Mutation
        mut_mask = rand(pop_size, chrom_len) < base_mut_rate;
        pop = xor(children, mut_mask);
        pop = repair_population(pop, task_num, T, fog_num);
        
        % Elitism: Restore best
        pop(1, :) = best_theta';
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
