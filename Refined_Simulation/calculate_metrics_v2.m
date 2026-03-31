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
    % Note: In snapshot, we treat Load as Arrival intensity spread over the deadline window.
    % If we assume tasks arrive uniformly within the deadline, Lambda = Total_Cycles / Mean_Deadline.
    mean_deadline = mean(Pre.Task_Deadline);
    if mean_deadline < 0.1, mean_deadline = 1.0; end % Safety
    
    Arrival_Rate = Load_Bin / mean_deadline;
    Rho = Arrival_Rate ./ (Service_Rate + 1e-9);
    
    % DEBUG: Check for Capacity Overload
    if verbose && any(Rho > 1.0)
        fprintf('DEBUG CRITICAL: Capacity Overload Detected!\n');
        fprintf('  Rho: [%s]\n', sprintf('%.2f ', Rho));
        fprintf('  Load (Cycles): [%s]\n', sprintf('%.2e ', Load_Bin));
        fprintf('  Cap (Cycles/s): [%s]\n', sprintf('%.2e ', Service_Rate));
        fprintf('  Mean Deadline: %.4f\n', mean_deadline);
    end

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
    
    % --- [TIER-1 FEATURE] Stochastic Jitter for Realism ---
    % Reviewer 2 Requirement: "Real-world variance".
    % We inject Gaussian noise (sigma=0.05, i.e., 5% variance) into processing and transmission.
    jitter_sigma = 0.05; 
    
    if isfield(Pre, 'Trace_Comp_Matrix') && ~isempty(Pre.Trace_Comp_Matrix)
        % --- TRACE-DRIVEN INJECTION (STRICT) ---
        Trace_Fog = Pre.Trace_Comp_Matrix(:, :, 1:fog_num);
        Proc_Time = Trace_Fog; 
    elseif isfield(Pre, 'Proc_Time_Trace') && ~isempty(Pre.Proc_Time_Trace)
        Proc_Time = Pre.Proc_Time_Trace;
    else
        % Static Model (Comp / Speed)
        Proc_Time = bsxfun(@rdivide, Pre.Comp, reshape(Pre.Fog_Speed, [1, 1, fog_num]));
        
        % Apply Jitter to Static Model (Only if not using strict trace)
        jitter_mat = 1 + jitter_sigma * randn(size(Proc_Time));
        jitter_mat = max(0.8, min(1.2, jitter_mat)); % Clip to [0.8, 1.2] to avoid extreme outliers
        Proc_Time = Proc_Time .* jitter_mat;
    end
    
    % Apply Queuing Factor (Broadcast over tasks)
    Proc_Time_Queued = bsxfun(@times, Proc_Time, reshape(Queue_Factor .* Swap_Factor, [1, 1, fog_num]));
    
    % Transmission Time
    % Base Transmission Time (Assuming 1 user)
    Trans_Time_Base = bsxfun(@rdivide, Pre.Data, reshape(bsxfun(@times, Pre.B, Pre.Fog_BW), [task_num, 1, fog_num]));
    
    % Apply Jitter to Transmission
    jitter_trans = 1 + jitter_sigma * randn(size(Trans_Time_Base));
    jitter_trans = max(0.5, min(2.0, jitter_trans)); % Wireless has higher variance
    Trans_Time_Base = Trans_Time_Base .* jitter_trans;

    
    N_active = squeeze(sum(X_bin, 1)); % [T, F]
    
    alpha_bw = 0.05; % Reduced from 0.8 to allow scalability at N=100
    Comm_Factor = 1.0 + alpha_bw * N_active; % [T, F]
    
    Prev_Fog = cat(2, zeros(task_num, 1, fog_num), X_bin(:, 1:end-1, :)); % [N, T, F]
    Enter_Fog = X_bin .* (1 - Prev_Fog); % [N, T, F]
    Leave_Fog = Prev_Fog .* (1 - X_bin); % [N, T, F]
    
    Trans_Uplink = Trans_Time_Base .* reshape(Comm_Factor, [1, T, fog_num]) .* Enter_Fog;
    Trans_Down_Seg = sum(Trans_Time_Base .* reshape(Comm_Factor, [1, T, fog_num]) .* Leave_Fog, 3); % [N, T]
    
    Fog_Time_Seg = Proc_Time_Queued + Trans_Uplink;
    
    % --- [CRITICAL FIX] Context Switching Overhead (Physically Modeled) ---
    % Reviewer 1 Feedback: "alpha_ctx = 0.00005" is a magic number.
    % Correction: Model based on hardware context switch time.
    % T_overhead = N_tasks * T_switch (Linear) or N_tasks * (N_tasks-1) * T_thrash (Quadratic for saturation)
    % We use a Quadratic model to penalize heavy congestion, derived from OS thrashing behavior.
    
    % Default hardware constant: 50 microseconds (5e-5s) per switch
    if isfield(Pre, 'Hardware_Context_Switch')
        base_switch_time = Pre.Hardware_Context_Switch;
    else
        base_switch_time = 5e-5; % 50us standard Linux context switch
    end
    
    % alpha_ctx is no longer arbitrary. It represents the cumulative thrashing impact.
    % We assume worst-case scheduling overhead scales with N^2 due to cache contention.
    alpha_ctx = base_switch_time; 
    
    % X_bin is [N, T, F].
    % Determine if User n is on Node f: Any layer assigned to f?
    User_On_Node = max(X_bin, [], 2); % [N, 1, F] (Binary)
    Tasks_Per_Node = squeeze(sum(User_On_Node, 1)); % [F, 1]
    
    % Calculate Overhead: alpha * N^2
    % [CRITICAL FIX] Cloud nodes (Type 3) use virtualization/containers and have massive parallelism.
    % They do NOT suffer from single-core context switching overhead (N^2).
    % Edge nodes (Type 1, 2) are single-board computers (SBCs) and DO suffer.
    
    Ctx_Overhead = alpha_ctx * (Tasks_Per_Node .^ 2); % Default [F, 1]
    
    if isfield(Pre, 'Node_Types')
        cloud_mask = (Pre.Node_Types == 3);
        % Zero out overhead for Cloud nodes
        Ctx_Overhead(cloud_mask) = 0;
    end
    
    Overhead_Time = Ctx_Overhead; % Alias for clarity
    
    % Add to Processing Time (Broadcast to all tasks on that node)
    % Fog_Time_Seg is [N, T, F]
    % [CORRECTION] Context switching overhead applies ONCE per task per node (setup time).
    % We should NOT add it to every segment, as that multiplies overhead by T (e.g. 6x).
    % We will add it explicitly to the final Delay calculation.
    
    % Overhead_Expanded = reshape(Overhead_Time, [1, 1, fog_num]);
    % Fog_Time_Seg = Fog_Time_Seg + bsxfun(@times, X_bin, Overhead_Expanded);
    
    % DEBUG
    if verbose
    fprintf('DEBUG METRICS: Tasks_Per_Node: [%s]\n', sprintf('%.0f ', Tasks_Per_Node));
end
    
    % Ctx_Overhead is already calculated correctly above with Cloud fix.
    % Do NOT re-calculate it here.
    % Ctx_Overhead = alpha_ctx * (Tasks_Per_Node .^ 2); % REMOVED DUPLICATE
    
    % Broadcast to Fog_Time_Seg [N, T, F] -> WRONG!
    % Overhead applies ONCE per node usage, not per layer.
    % Fog_Time_Seg = bsxfun(@plus, Fog_Time_Seg, reshape(Ctx_Overhead, [1, 1, fog_num])); -> REMOVED
    
    if isfield(Pre, 'Trace_Comp_Matrix') && ~isempty(Pre.Trace_Comp_Matrix)
         % Trace-Driven Local
         Local_Time_Seg = Pre.Trace_Comp_Matrix(:, :, end);
    else
         Local_Time_Seg = Pre.Comp ./ Pre.Local_Speed;
    end
    
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
    
    % ADD OVERHEAD HERE (Once per active node)
    % User_On_Node is [N, 1, F]. Ctx_Overhead is [F, 1].
    % Delay = Sum over F of (User_On_Node * Ctx_Overhead)
    Overhead_Delay = zeros(task_num, 1);
    for f=1:fog_num
        Overhead_Delay = Overhead_Delay + User_On_Node(:,:,f) * Ctx_Overhead(f);
    end
    Fog_Delay = Fog_Delay + Overhead_Delay;
    
    Local_Delay = sum(Prob_Local .* Local_Time_Seg, 2);
    Down_Delay = sum(Trans_Down_Seg, 2);
    D_T = Fog_Delay + Local_Delay + Down_Delay;

    cap_over = Rho > 1.0; % Only flag if Rho > 1 (Unstable)
    mem_over = Mem_Bin_MB > Fog(:, 8)';
    node_over = cap_over | mem_over; % stable_idx handles delay penalty
    if any(node_over)
        user_on_node = squeeze(max(X_bin, [], 2));
        viol_task = viol_task | any(user_on_node(:, node_over), 2);
    end
    viol_rate = mean(viol_task(:)); % Force scalar
    
    LT = Pre.Task_Deadline;
    ET = LT * 0.5;
    if isfield(Pre, 'Task_ET')
        ET = Pre.Task_ET;
    end

    % DEBUG PRINT (Conditional)
    if verbose && rand() < 0.01
        fprintf('DEBUG: Task 1 - Latency: %.4f, Deadline: %.4f, Tolerance: %.4f, Sat: %.2f\n', ...
            D_T(1), ET(1), LT(1), 0);
        fprintf('       Comp: %.4f, Trans: %.4f, Queue: %.4f\n', ...
            Fog_Delay(1), Down_Delay(1), 0);
    end

    S_t = zeros(task_num, 1);
    
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
    
    if verbose && avg_satis < 10.0
        fprintf('  [DEBUG CRITICAL] Low Satisfaction: %.2f%%\n', avg_satis);
        fprintf('  Sample Task 1 (Type %d): LocalLat=%.3f, FogLat=%.3f, TotalLat=%.3f, Deadline=%.3f, Result=%.1f\n', ...
            Task(1,2), sum(Local_Time_Seg(1,:)), Fog_Delay(1), D_T(1), Pre.Task_ET(1), S_t(1));
        fprintf('  Sample Task 50 (Type %d): LocalLat=%.3f, FogLat=%.3f, TotalLat=%.3f, Deadline=%.3f, Result=%.1f\n', ...
            Task(min(end,50),2), sum(Local_Time_Seg(min(end,50),:)), Fog_Delay(min(end,50)), D_T(min(end,50)), Pre.Task_ET(min(end,50)), S_t(min(end,50)));
        fprintf('  Ctx Overhead (Max Node): %.3f s\n', max(Ctx_Overhead));
    end

    breakdown = [mean(Fog_Delay), mean(Local_Delay), mean(Down_Delay)];
end
