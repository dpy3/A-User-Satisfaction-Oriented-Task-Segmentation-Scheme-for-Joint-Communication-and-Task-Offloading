function theta_bin = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data)
    % GREEDY_SOLVER_DNN
    % Heuristic baseline: Assigns each task to the best available node (Min Latency)
    % Updates Load dynamically.
    
    global task_num fog_num T;
    
    % Use Tier1 builder for consistency
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    % Initialize State
    Load = zeros(fog_num, 1);
    MemUsg = zeros(fog_num, 1);
    Cap = Fog(:, 7);
    MemLim = Fog(:, 8); % Assuming Col 8 exists
    if size(Fog, 2) < 8, MemLim = inf(fog_num, 1); end
    
    theta_bin = zeros(task_num, T, fog_num);
    
    % Randomize order to avoid bias? NO.
    % IMPROVEMENT: Sort by Deadline Tightness (Ascending)
    % Tasks with tighter deadlines should be scheduled first.
    deadlines = Task(:, 5);
    [~, task_order] = sort(deadlines, 'ascend');
    
    % Alternative: Sort by Computational Density (Descend)
    % [~, task_order] = sort(Task(:, 1), 'descend'); 
    
    for i = task_order'
        for t = 1:T
            % Evaluate Options
            % Option 1: Local
            lat_local = Pre.Local_Lat(i, t);
            best_lat = lat_local;
            best_f = -1; % -1 means Local
            
            % Option 2: Fog Nodes
            for f = 1:fog_num
                % Check Constraints
                if Load(f) + Pre.Comp(i, t) <= Cap(f) && ...
                   MemUsg(f) + Pre.Data(i, t) <= MemLim(f)
               
                    % Estimate Latency (M/M/1 approx)
                    rho = Load(f) / (Cap(f) + 1e-9);
                    rho = min(rho, 0.99);
                    Q = 1 + rho / (2*(1-rho));
                    
                    proc_time = (Pre.Comp(i, t) / Fog(f, 4)) * Q;
                    trans_time = Pre.Trans(i, t, f);
                    
                    lat_fog = proc_time + trans_time;
                    
                    if lat_fog < best_lat
                        best_lat = lat_fog;
                        best_f = f;
                    end
                end
            end
            
            % Assign
            if best_f > 0
                theta_bin(i, t, best_f) = 1;
                Load(best_f) = Load(best_f) + Pre.Comp(i, t);
                MemUsg(best_f) = MemUsg(best_f) + Pre.Data(i, t);
            else
                % Local: Do nothing (all zeros in theta_bin)
            end
        end
    end
end
