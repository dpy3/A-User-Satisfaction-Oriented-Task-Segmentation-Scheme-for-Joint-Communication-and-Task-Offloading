function [avg_satis, viol_rate, breakdown, D_T, S_t, viol_task] = calculate_metrics_v2(theta, Task, Fog, Thing, DNN_Data, varargin)
    % CALCULATE_METRICS_V2
    % Calculates system metrics: Average Satisfaction (%), Violation Rate, and Breakdown.
    % Returns vectors D_T (Latency), S_t (Satisfaction), viol_task (Violation) for analysis.
    % Consistent with ALM_Solver_Wrapper logic.
    
    global task_num fog_num T;
    
    % --- Ensure Dimensions are Valid ---
    % If global vars are empty (or mismatched), infer from inputs
    if isempty(task_num) || isempty(fog_num) || isempty(T) || T == 0
         task_num = size(Task, 1);
         fog_num = size(Fog, 1);
         if iscell(DNN_Data)
             T = length(DNN_Data{1}.comp);
         elseif isstruct(DNN_Data) && numel(DNN_Data) > 1
             T = length(DNN_Data(1).comp); % Handle struct array
         else
             T = length(DNN_Data.comp);
         end
    end
    
    % Safety check: If inputs differ from globals, trust inputs for this call
    if task_num ~= size(Task, 1) || fog_num ~= size(Fog, 1)
         task_num = size(Task, 1);
         fog_num = size(Fog, 1);
    end
    
    verbose = false; % Default to silent
    
    Pre = [];
    if ~isempty(varargin)
        maybe_pre = varargin{1};
        if isstruct(maybe_pre) && isfield(maybe_pre, 'Comp') && isfield(maybe_pre, 'Data')
            Pre = maybe_pre;
        end
    end
    if isempty(Pre)
        % Use Tier1 builder for consistency and robustness
        Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    end
    
    % (Removed redundant manual reconstruction)

    % Binarize Theta
    theta_bin = double(theta > 0.5);
    
    % DEBUG
    if numel(theta_bin) ~= task_num * T * fog_num
        fprintf('ERROR: Reshape Mismatch! Theta: %d, Expected: %d * %d * %d = %d\n', numel(theta_bin), task_num, T, fog_num, task_num * T * fog_num);
        % Try to infer T from theta if possible
        T_inferred = numel(theta_bin) / (task_num * fog_num);
        if mod(T_inferred, 1) == 0
             fprintf('WARNING: Inferring T = %d from theta (Global T = %d)\n', T_inferred, T);
             T = T_inferred;
        end
    end
    
    X_bin = reshape(theta_bin, [task_num, T, fog_num]);
    
    % DEBUG SIZES
    if verbose || true
        % fprintf('DEBUG: X_bin: [%d %d %d], Pre.Comp: [%d %d]\n', size(X_bin), size(Pre.Comp));
    end
    
    % --- CRITICAL FIX: Dimension Alignment ---
    % Ensure Pre.Comp matches T. If not, trim or pad, or re-infer T.
    if size(Pre.Comp, 2) ~= T
         if verbose, fprintf('WARNING: Pre.Comp T=%d, but Global T=%d. Adjusting Pre.\n', size(Pre.Comp, 2), T); end
         % Trust T from X_bin
         if size(X_bin, 2) == size(Pre.Comp, 2)
             T = size(X_bin, 2);
         end
    end
    
    % Ensure X_bin matches Pre.Comp dimensions for bsxfun
    if size(X_bin, 1) ~= size(Pre.Comp, 1) || size(X_bin, 2) ~= size(Pre.Comp, 2)
        % Mismatch!
        fprintf('CRITICAL ERROR: Dimension Mismatch in calculate_metrics_v2!\n');
        fprintf('  X_bin: [%d %d %d]\n', size(X_bin));
        fprintf('  Pre.Comp: [%d %d]\n', size(Pre.Comp));
        
        % Emergency Fix: Resize Pre to match X_bin (Assuming X_bin is correct for the solution)
        % This happens if Task/DNN_Data changed but Pre was cached.
        Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
        
        if size(X_bin, 1) ~= size(Pre.Comp, 1) || size(X_bin, 2) ~= size(Pre.Comp, 2)
             error('calculate_metrics_v2: Unresolvable dimension mismatch.');
        end
    end

    Sum_Bin = sum(X_bin, 3);
    viol_task = any(Sum_Bin > 1.1, 2);
    Load_Bin = squeeze(sum(sum(bsxfun(@times, X_bin, Pre.Comp), 1), 2))'; 
    Mem_Bin = squeeze(sum(sum(bsxfun(@times, X_bin, Pre.Data), 1), 2))';
    Mem_Bin_MB = Mem_Bin / 8e6;
    
    % 2. User Satisfaction
    % Calculate Load and Queuing Delay (M/M/1)
    % Load_Bin: Total Cycles assigned to each Fog Node
    % Fog(:, 7): Service Rate (Cycles/s)
    
    Service_Rate = Fog(:, 7)'; % Vector [1, F]
    Arrival_Rate = Load_Bin;   % Vector [1, F] (Total Cycles requested)
    
    % Calculate Utilization rho
    % Note: In snapshot, we treat Load as Arrival intensity
    Rho = Arrival_Rate ./ (Service_Rate + 1e-9);
    
    % Strict M/D/1 Queuing (No Cap!)
    % If Rho >= 1, the system is unstable (Infinite Delay).
    Rho = Arrival_Rate ./ (Service_Rate + 1e-9);
    
    Queue_Factor = ones(size(Rho));
    
    % Stable Region (rho < 1)
    stable_idx = Rho < 0.999;
    Queue_Factor(stable_idx) = 1 + Rho(stable_idx) ./ (2 * (1 - Rho(stable_idx)));
    
    % Unstable Region (rho >= 1) -> Penalty
    % Massive delay penalty for saturation
    Queue_Factor(~stable_idx) = 1e4;

    
    % Memory Swap Penalty Factor
    % If Mem > Cap, performance degrades drastically (Swapping)
    % FIX: Use Mem_Bin_MB (MB) instead of Mem_Bin (Bits)
    Mem_Usage = Mem_Bin_MB ./ (Fog(:, 8)' + 1e-9);
    Swap_Factor = ones(size(Mem_Usage));
    % Soft penalty for approaching limit, Hard penalty for exceeding
    Swap_Factor(Mem_Usage > 1.0) = 10.0 * Mem_Usage(Mem_Usage > 1.0); % 10x penalty for overflow
    
    % Fog Processing: (Comp / Fog_Speed) * Queue_Factor * Swap_Factor
    % Base Processing Time
    Proc_Time = bsxfun(@rdivide, Pre.Comp, reshape(Pre.Fog_Speed, [1, 1, fog_num]));
    
    % Apply Queuing Factor (Broadcast over tasks)
    Proc_Time_Queued = bsxfun(@times, Proc_Time, reshape(Queue_Factor .* Swap_Factor, [1, 1, fog_num]));
    
    % Transmission Time
    % Dynamic Bandwidth Sharing (FDMA-like) + DNN Segmentation Rule:
    % A transmission occurs only when a segment is assigned to a fog node AND
    % its previous segment was not on the same fog node. This matches the paper's
    % "only when consecutive segments are assigned to different execution tiers".
    
    % Base Transmission Time (Assuming 1 user)
    Trans_Time_Base = bsxfun(@rdivide, Pre.Data, reshape(bsxfun(@times, Pre.B, Pre.Fog_BW), [task_num, 1, fog_num]));
    
    N_active = squeeze(sum(X_bin, 1)); % [T, F]
    
    alpha_bw = 0.8;
    Comm_Factor = 1.0 + alpha_bw * N_active; % [T, F]
    
    Prev_Fog = cat(2, zeros(task_num, 1, fog_num), X_bin(:, 1:end-1, :)); % [N, T, F]
    Enter_Fog = X_bin .* (1 - Prev_Fog); % [N, T, F]
    Leave_Fog = Prev_Fog .* (1 - X_bin); % [N, T, F]
    
    Trans_Uplink = Trans_Time_Base .* reshape(Comm_Factor, [1, T, fog_num]) .* Enter_Fog;
    Trans_Down_Seg = sum(Trans_Time_Base .* reshape(Comm_Factor, [1, T, fog_num]) .* Leave_Fog, 3); % [N, T]
    
    Fog_Time_Seg = Proc_Time_Queued + Trans_Uplink;
    
    % --- [CRITICAL FIX] Context Switching Overhead (Reviewer 2) ---
    % Add N^2 Overhead to Fog Latency for Realism
    % Overhead applies to ALL tasks on the node.
    % Formula: T_overhead = alpha * (N_tasks_on_node)^2
     % FIX: Count UNIQUE USERS, not SEGMENTS.
    
    alpha_ctx = 0.0002; % Calibrated to 0.0002 for N=100 Scale (0.5s max overhead)
    
    % X_bin is [N, T, F].
    % Determine if User n is on Node f: Any layer assigned to f?
    User_On_Node = max(X_bin, [], 2); % [N, 1, F] (Binary)
    Tasks_Per_Node = squeeze(sum(User_On_Node, 1)); % [F, 1]
    
    Ctx_Overhead = alpha_ctx * (Tasks_Per_Node .^ 2); % [F, 1]
    
    % Broadcast to Fog_Time_Seg [N, T, F]
    Fog_Time_Seg = bsxfun(@plus, Fog_Time_Seg, reshape(Ctx_Overhead, [1, 1, fog_num]));
    
    Local_Time_Seg = Pre.Comp ./ Pre.Local_Speed;
    
    X_Sum_F = sum(X_bin, 3);
    Prob_Local = 1 - X_Sum_F;

    % --- [CRITICAL FIX] Local Queuing (Reviewer 2) ---
    % Model Local Device as M/M/1 Queue (or M/M/c if multi-core)
    % Assumption: Local device processes tasks sequentially (M/M/1)
    % Since each user has their OWN local device and only 1 task,
    % there is NO queuing delay from other users.
    % Latency is simply Workload / Speed.
    
    % However, if we view segments as arriving sequentially, it's just serial processing.
    % So Q_Factor is 1.0.
    
    Local_Q_Factor = 1.0;
    
    % Apply to Local_Time_Seg
    % Broadcast Q_Factor [N, 1] to [N, T]
    Local_Time_Seg = bsxfun(@times, Local_Time_Seg, Local_Q_Factor);
    
    Fog_Delay = sum(sum(X_bin .* Fog_Time_Seg, 3), 2);
    Local_Delay = sum(Prob_Local .* Local_Time_Seg, 2);
    Down_Delay = sum(Trans_Down_Seg, 2);
    D_T = Fog_Delay + Local_Delay + Down_Delay;

    cap_over = Load_Bin > Fog(:, 7)';
    mem_over = Mem_Bin_MB > Fog(:, 8)';
    node_over = cap_over | mem_over | ~stable_idx;
    if any(node_over)
        user_on_node = squeeze(max(X_bin, [], 2));
        viol_task = viol_task | any(user_on_node(:, node_over), 2);
    end
    viol_rate = mean(viol_task(:)); % Force scalar
    
    S_t = zeros(task_num, 1);
    LT = Pre.Task_Deadline;
    ET = LT * 0.5;
    % FIX: ET should be strict deadline.
    % If d < ET, S=1. If d > LT, S=0.
    % Use Pre.Task_ET directly if available
    if isfield(Pre, 'Task_ET')
        ET = Pre.Task_ET;
    end
    
    S_LT = 0;
    
    for i = 1:task_num
        d = D_T(i);
        if d <= ET(i)
            S_t(i) = 1.0;
        elseif d <= LT(i)
            S_t(i) = S_LT + (1 - S_LT) * (LT(i) - d) / (LT(i) - ET(i));
        else
            S_t(i) = 0;
        end
    end
    
    avg_satis = mean(S_t) * 100;

    % DEBUG PRINT
    % fprintf('DEBUG: Rho=['); fprintf('%.2f ', Rho(1:min(5,end))); fprintf('], QF=['); fprintf('%.1f ', Queue_Factor(1:min(5,end))); 
    % fprintf('], AvgDelay=%.3f, AvgSat=%.2f\n', mean(D_T), avg_satis);
    
    if verbose
         fprintf('DEBUG: FogSpeed=%.1f, LocalSpeed=%.1f, TransTime=%.3f\n', Pre.Fog_Speed(1), Pre.Local_Speed(1), mean(Trans_Uplink(:)) + mean(Trans_Down_Seg(:)));
    end
    
    if avg_satis < 10.0
        fprintf('  [DEBUG CRITICAL] Low Satisfaction: %.2f%%\n', avg_satis);
        fprintf('  Sample Task 1 (Type %d): LocalLat=%.3f, FogLat=%.3f, Deadline=%.3f, Result=%.1f\n', ...
            Task(1,2), sum(Local_Time_Seg(1,:)), Fog_Delay(1), Pre.Task_ET(1), S_t(1));
        fprintf('  Sample Task 50 (Type %d): LocalLat=%.3f, FogLat=%.3f, Deadline=%.3f, Result=%.1f\n', ...
            Task(min(end,50),2), sum(Local_Time_Seg(min(end,50),:)), Fog_Delay(min(end,50)), Pre.Task_ET(min(end,50)), S_t(min(end,50)));
        fprintf('  Ctx Overhead (Max Node): %.3f s\n', max(Ctx_Overhead));
    end

    breakdown = [mean(Fog_Delay), mean(Local_Delay), mean(Down_Delay)];
end
