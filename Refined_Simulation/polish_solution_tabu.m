function theta_polished = polish_solution_tabu(theta_bin, Pre, Fog, Thing)
    % POLISH_SOLUTION_TABU: Advanced Local Search
    % V2: Includes "Smart Repair", "Migration", and "Swapping"
    
    [N, T, F_in] = size(theta_bin);
    [~, ~, F_real] = size(Pre.Comp_Exp);
    F = F_real;
    
    theta_polished = theta_bin;
    
    % --- 1. Smart Repair (Constraints) ---
    theta_fog = theta_polished(:, :, 1:F);
    Load = squeeze(sum(sum(theta_fog .* Pre.Comp_Exp, 1), 2));
    Cap = Fog(:, 7);
    Data_MB = Pre.Data_Exp / 8e6;
    Mem = squeeze(sum(sum(theta_fog .* Data_MB, 1), 2));
    MemCap = Fog(:, 8);
    
    for iter = 1:10
        overloaded = find((Load > Cap) | (Mem > MemCap));
        if isempty(overloaded), break; end
        
        for f = overloaded'
            [users, segs] = find(theta_polished(:, :, f));
            if isempty(users), continue; end
            
            % Sort by Impact
            impacts = zeros(length(users), 1);
            for k = 1:length(users), impacts(k) = Pre.Comp_Exp(users(k), segs(k), f); end
            [~, idx] = sort(impacts, 'descend');
            
            for k = 1:length(users)
                if Load(f) <= Cap(f), break; end
                u = users(idx(k)); s = segs(idx(k));
                
                % Try move to underloaded
                % Relaxed constraint: Allow moving to any node with capacity, not just <90%
                under = find((Load < Cap) & (Mem < MemCap)); 
                moved = false;
                
                % Prioritize faster nodes in underloaded set
                if ~isempty(under)
                    [~, s_idx] = sort(Fog(under, 4), 'descend');
                    for target = under(s_idx)'
                         req = Pre.Comp_Exp(u, s, target);
                         mem_req = Data_MB(u, s, target);
                         if Load(target) + req <= Cap(target) && Mem(target) + mem_req <= MemCap(target)
                             theta_polished(u, s, f) = 0;
                             theta_polished(u, s, target) = 1;
                             Load(f) = Load(f) - impacts(idx(k));
                             Load(target) = Load(target) + req;
                             Mem(f) = Mem(f) - Data_MB(u, s, f);
                             Mem(target) = Mem(target) + mem_req;
                             moved = true;
                             break;
                         end
                    end
                end
                
                % If fail, move to Local
                if ~moved
                    theta_polished(u, s, f) = 0;
                    if F_in > F, theta_polished(u, s, F_in) = 1; end
                    Load(f) = Load(f) - impacts(idx(k));
                    Mem(f) = Mem(f) - Data_MB(u, s, f);
                end
            end
        end
    end
    
    % --- 2. Hill Climbing (Satisfaction) ---
    % We iterate through tasks and try to improve their location
    
    % Cache Latencies/Sat to avoid recomputing everything
    % Actually, quick_latency is fast enough.
    
    % Randomize order
    order = randperm(N);
    
    for i = order
        % Get Current Status
        curr_lat = quick_latency(theta_polished(i,:,:), Pre, Fog, Load, Cap, i);
        curr_sat = quick_satisfaction(curr_lat, Pre.Deadline(i));
        
        if curr_sat >= 100, continue; end % Already maxed
        
        best_theta = theta_polished(i,:,:);
        best_sat = curr_sat;
        best_lat = curr_lat;
        improved = false;
        
        curr_load = zeros(F, 1);
        curr_mem = zeros(F, 1);
        for t = 1:T
            for f = 1:F
                if theta_polished(i,t,f) == 1
                    curr_load(f) = curr_load(f) + Pre.Comp_Exp(i,t,f);
                    curr_mem(f) = curr_mem(f) + Data_MB(i,t,f);
                end
            end
        end
        
        % Action 1: Migrate Entire Task (Most effective for DNN)
        for cand = 0:F
            % Construct Candidate
            cand_theta = zeros(1, T, F_in);
            if cand == 0
                if F_in > F, cand_theta(1,:,F_in) = 1; end
                % Always feasible locally (infinite cap assumption in model, usually)
                load_test = Load - curr_load;
                mem_test = Mem - curr_mem;
            else
                % Check Capacity
                needed = sum(Pre.Comp_Exp(i,:,cand));
                % Note: We must subtract current load if we are already on 'cand'? 
                % But we are moving *entire* task.
                % If we are currently on 'cand' partially, we need to be careful.
                % Simplified: Just check if (Load + needed) < Cap. 
                % This is conservative (doesn't account for self-removal). 
                % It's fine for safety.
                mem_needed = sum(Data_MB(i,:,cand));
                load_test = Load - curr_load;
                mem_test = Mem - curr_mem;
                if load_test(cand) + needed > Cap(cand), continue; end
                if mem_test(cand) + mem_needed > MemCap(cand), continue; end
                load_test(cand) = load_test(cand) + needed;
                mem_test(cand) = mem_test(cand) + mem_needed;
                cand_theta(1,:,cand) = 1;
            end
            
            % Eval
            lat = quick_latency(cand_theta, Pre, Fog, load_test, Cap, i);
            sat = quick_satisfaction(lat, Pre.Deadline(i));
            
            if sat > best_sat + 1e-4 || (abs(sat - best_sat) < 1e-4 && lat < best_lat - 1e-4)
                best_sat = sat;
                best_lat = lat;
                best_theta = cand_theta;
                improved = true;
            end
        end
        
        if improved
            % Commit
            % Update Load (Remove old, Add new)
            % 1. Remove old
            for t=1:T
                for f=1:F
                    if theta_polished(i,t,f) == 1
                        Load(f) = Load(f) - Pre.Comp_Exp(i,t,f);
                        Mem(f) = Mem(f) - Data_MB(i,t,f);
                    end
                end
            end
            
            % 2. Update Theta
            theta_polished(i,:,:) = best_theta;
            
            % 3. Add new
            for t=1:T
                for f=1:F
                    if theta_polished(i,t,f) == 1
                        Load(f) = Load(f) + Pre.Comp_Exp(i,t,f);
                        Mem(f) = Mem(f) + Data_MB(i,t,f);
                    end
                end
            end
        end
    end
end

function lat = quick_latency(theta_i, Pre, Fog, Load, Cap, u_idx)
    [~, T, F_dim] = size(theta_i);
    lat = 0;
    
    real_fog_num = length(Load);
    
    % Reconstruct Delay
    for t = 1:T
        loc = 0;
        for f=1:F_dim, if theta_i(1,t,f)==1, loc=f; break; end; end
        if loc > real_fog_num, loc = 0; end
        
        if loc == 0
            lat = lat + Pre.Local_Lat(u_idx, t);
        else
            % Fog: M/D/1 with Linear Overload
            rho = Load(loc) / (Cap(loc) + 1e-9);
            
            % Match Evaluation Metric exactly for consistency
            if rho <= 0.99
                Q = 1 + rho ./ (2 * (1 - rho));
            else
                % At 0.99, Q = 1 + 0.99/0.02 = 50.5
                % Slope dQ/drho at 0.99 = 0.5 / (0.01^2) = 5000
                Q = 50.5 + 5000 * (rho - 0.99);
            end
            
            comp_time = (Pre.Comp(u_idx,t) / Fog(loc,4)) * Q;
            
            % Trans
            trans_time = Pre.Trans(u_idx,t,loc); 
            if t > 1
                prev_loc = 0;
                for pf=1:F_dim, if theta_i(1,t-1,pf)==1, prev_loc=pf; break; end; end
                if prev_loc > real_fog_num, prev_loc = 0; end
                if prev_loc == loc, trans_time = 0; end
            end
            
            lat = lat + comp_time + trans_time;
        end
    end
end

function sat = quick_satisfaction(lat, deadline)
    if lat <= deadline
        sat = 100;
    elseif lat >= 1.5 * deadline
        sat = 0;
    else
        sat = 100 * (1.5 * deadline - lat) / (0.5 * deadline);
    end
end
