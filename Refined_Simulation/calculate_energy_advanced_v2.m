function [E_total, breakdown] = calculate_energy_advanced_v2(theta, Task, Fog, Thing, DNN_Data, varargin)
    % global task_num fog_num T; % Don't rely on global
    
    fog_num = size(Fog, 1);
    task_num = size(Task, 1);
    if iscell(DNN_Data), T = length(DNN_Data{1}.comp); else, T = length(DNN_Data.comp); end
    if isvector(theta)
        theta = reshape(theta, [task_num, T, fog_num]);
    elseif ndims(theta) == 2 && size(theta, 1) == task_num && size(theta, 2) == T * fog_num
        theta = reshape(theta, [task_num, T, fog_num]);
    end
    if ndims(theta) == 3
        [task_num, T, fog_num] = size(theta);
    end
    
    Pre = [];
    if ~isempty(varargin)
        maybe_pre = varargin{1};
        if isstruct(maybe_pre) && isfield(maybe_pre, 'Comp') && isfield(maybe_pre, 'Data')
            Pre = maybe_pre;
        end
    end
    if isempty(Pre)
        Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    end
    
    theta_bin = double(theta > 0.5);
    if ndims(theta_bin) == 3
        X_bin = theta_bin;
    else
        X_bin = reshape(theta_bin, [task_num, T, fog_num]);
    end
    
    X_Sum_F = sum(X_bin, 3);
    Prob_Local = 1 - X_Sum_F;
    
    E_fog_proc = 0;
    for f = 1:fog_num
        % Pre.Comp can be [N, T] or [N, T, F]. Use Pre.Comp_Exp if available or assume Pre.Comp is [N, T]
        if isfield(Pre, 'Comp_Exp')
             comp_load = Pre.Comp_Exp(:, :, f);
             data_load = Pre.Data_Exp(:, :, f);
        else
             comp_load = Pre.Comp;
             data_load = Pre.Data;
        end
        
        % Check Dimensions
        if size(comp_load, 1) ~= size(X_bin, 1)
             % Dimension Mismatch! Likely Pre is stale or X_bin is wrong.
             % Fallback: Resize comp_load to match X_bin
             % fprintf('Debug: Resizing comp_load from %dx%d to %dx%d\n', size(comp_load,1), size(comp_load,2), size(X_bin,1), size(X_bin,2));
             if size(comp_load, 1) < size(X_bin, 1)
                 % Expand? No, likely Pre is for N=50 but we are at N=80?
                 % Or Pre is for N=80 but X_bin is [80, T] and comp_load is [80, T].
                 error('Dimension Mismatch: X_bin(%d) vs Comp(%d)', size(X_bin, 1), size(comp_load, 1));
             end
        end
        
        load_f = sum(sum(X_bin(:, :, f) .* comp_load));
        mem_f = sum(sum(X_bin(:, :, f) .* data_load));
        
        % Base Processing Energy
        % E = Load (Cycles) * Energy_Per_Cycle
        % Fog(f, 5) is Energy Coeff (approx 1e-27 * f^2) ? No, Fog(f,5) is usually k.
        % Check usage: e_proc = load_f * Fog(f, 5) * (Fog(f, 4)^2);
        % If Fog(f, 4) is speed (GFLOPs or Hz), then Load must be scaled?
        % Pre.Comp is in GFLOPs. Fog(f, 4) is GFLOPs.
        % Load_f (GFLOPs) / Speed (GFLOPs/s) = Time (s)
        % Power = k * Speed^3
        % Energy = Power * Time = k * Speed^2 * Load_f
        
        k_fog = Fog(f, 5); % 1e-27 range?
        if k_fog < 1e-20, k_fog = 1e-10; end % Safety floor if not set
        
        % Note: Fog(f, 4) is typically ~100.0 (Speed).
        % If k_fog is small, E is small.
        % Let's assume typical Power ~ 10W.
        % P = k * f^3 -> k = P / f^3
        % If P=10, f=100 -> k = 10 / 1e6 = 1e-5.
        
        % Check if Fog(:,5) is reasonable
         if k_fog < 1e-15 % Likely unset or physics k
              % Use calibrated model
              P_peak = 20.0; % 20W for server
              speed = Fog(f, 4);
              k_calib = P_peak / (speed^3 + 1e-9);
              e_proc = load_f * k_calib * (speed^2);
              % fprintf('Debug: Using Calibrated k=%.2e for Node %d. Speed=%.1f, Load=%.1f, E=%.4f\n', k_calib, f, speed, load_f, e_proc);
         else
              e_proc = load_f * k_fog * (Fog(f, 4)^2);
              % fprintf('Debug: Using Given k=%.2e for Node %d. Speed=%.1f, Load=%.1f, E=%.4f\n', k_fog, f, Fog(f, 4), load_f, e_proc);
         end
        
        % Memory Swap Energy Penalty
        mem_cap = Fog(f, 8);
        if mem_f > mem_cap
            excess = mem_f - mem_cap;
            e_swap = excess * 1e-6; 
            e_proc = e_proc + e_swap;
        end
        
        E_fog_proc = E_fog_proc + e_proc;
    end
    
    E_local_proc = 0;
    P_Local = 5.0;
    for i = 1:task_num
        load_l = sum(Prob_Local(i, :) .* Pre.Local_Lat(i, :));
        E_local_proc = E_local_proc + load_l * P_Local;
    end
    
    Trans_Time = bsxfun(@rdivide, Pre.Data, reshape(bsxfun(@times, Pre.B, Pre.Fog_BW), [task_num, 1, fog_num]));
    
    E_tail = 0;
    for i = 1:task_num
        thing_idx = Task(i, 4);
        p_tx = Thing(thing_idx, 6);
        trans_time_i = sum(sum(X_bin(i, :, :) .* Trans_Time(i, :, :)));
        E_tail = E_tail + trans_time_i * p_tx;
    end
    
    E_total = E_fog_proc + E_local_proc + E_tail;
    breakdown = [E_fog_proc, E_local_proc, E_tail];
end
