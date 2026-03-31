function theta_logits = smart_init_heuristic(Task, Fog, Thing, DNN_Data)
    % SMART_INIT_HEURISTIC: O(N) Iterative Load Balancing
    %
    % Strategy: Greedy-Balance
    % Iterate through tasks and assign to the node with the least *current*
    % estimated load (normalized by capacity).
    %
    % This ensures the initial population starts with a balanced load, 
    % minimizing N^2 context switching penalties immediately.
    %
    % Complexity: O(N * F)
    
    global task_num fog_num T;
    
    if isempty(task_num), task_num = size(Task, 1); end
    if isempty(fog_num), fog_num = size(Fog, 1); end
    
    % Pre-compute basic costs
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    theta_logits = zeros(task_num, T, fog_num + 1);
    
    % Track Current Load on Nodes (to balance)
    % Load = Sum(Comp) / Cap
    Current_Load = zeros(1, fog_num); 
    Current_Tasks = zeros(1, fog_num);
    
    Fog_Cap = Fog(:, 7)';
    
    % Logits for "Selected" vs "Not Selected"
    logit_high = 2.0;
    logit_low  = -2.0;
    
    for i = 1:task_num
        % Estimate Task Size (Avg over layers for simplicity or just total)
        task_comp = sum(Pre.Comp(i, :));
        
        % Check Local feasibility
        local_lat = task_comp / Pre.Local_Speed(i);
        deadline = Pre.Deadline(i);
        
        best_node = -1;
        min_score = inf;
        
        % Try Fog Nodes
        for f = 1:fog_num
            % Score = Current Load + Task Load
            % Normalize by Capacity
            load_est = (Current_Load(f) + task_comp) / Fog_Cap(f);
            
            % Add Overhead Penalty proxy (N^2)
            % (N+1)^2 - N^2 = 2N + 1
            overhead_cost = (Current_Tasks(f) * 2 + 1) * 0.0002 * 10.0; % Scale up to matter
            
            score = load_est + overhead_cost;
            
            if score < min_score
                min_score = score;
                best_node = f;
            end
        end
        
        % Decide: Local or Best Fog?
        % If Local meets deadline comfortably, use Local (save Fog for others)
        if local_lat < 0.8 * deadline
            % Use Local
             theta_logits(i, :, end) = logit_high;
             theta_logits(i, :, 1:fog_num) = logit_low;
        else
            % Use Best Fog
             theta_logits(i, :, best_node) = logit_high;
             theta_logits(i, :, 1:fog_num) = logit_low; % Reset others
             theta_logits(i, :, best_node) = logit_high; % Set best
             theta_logits(i, :, end) = logit_low;
             
             % Update State
             Current_Load(best_node) = Current_Load(best_node) + task_comp;
             Current_Tasks(best_node) = Current_Tasks(best_node) + 1;
        end
    end
    
    % Add Noise for Diversity (Essential for GA)
    theta_logits = theta_logits + randn(size(theta_logits)) * 0.5;
    
    % Scale down to prevent saturation (0.5 + 0.5 ~ 1.0 -> Sigmoid 0.73)
    theta_logits = theta_logits * 0.5;
    
    fprintf('[Smart-Init] Generated Balanced Logits (O(N*F) Greedy-Balance)\n');
end
