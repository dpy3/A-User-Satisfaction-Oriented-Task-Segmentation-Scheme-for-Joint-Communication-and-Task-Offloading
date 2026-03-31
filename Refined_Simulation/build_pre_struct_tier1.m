function Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data)
    % BUILD_PRE_STRUCT_TIER1: Pre-computes constants for ALM Solver
    %
    % Output Pre struct contains:
    % .Comp: [N, T] - Computation load (GFLOPs)
    % .Data: [N, T] - Data output size (bits)
    % .Comp_Exp: [N, T, F] - Replicated Comp for vectorized ops
    % .Data_Exp: [N, T, F] - Replicated Data for vectorized ops
    % .Local_Lat: [N, T] - Local execution time
    % .Trans: [N, T, F] - Transmission time to node F
    % .Deadline: [N, 1] - Task deadline (ET)
    % .Tolerance: [N, 1] - Task tolerance (LT)
    % .Proc_Time_Trace: [N, T, F] - Trace-driven latency (Multimodal)
    
    global task_num fog_num T;
    
    % ALWAYS update from input if available
    if nargin >= 1 && ~isempty(Task)
        task_num = size(Task, 1);
    end
    if nargin >= 2 && ~isempty(Fog)
        fog_num = size(Fog, 1);
    end
    
    % Force T update from DNN_Data if provided
    if nargin >= 4 && ~isempty(DNN_Data)
        if iscell(DNN_Data)
            max_len = 0;
            for d = 1:length(DNN_Data)
                max_len = max(max_len, length(DNN_Data{d}.comp));
            end
            T = max_len;
        else
            T = length(DNN_Data.comp);
        end
    elseif isempty(T)
        % Fallback or error
        error('DNN_Data not provided and T is empty');
    end
    
    % --- 1. Basic Extraction ---
    Comp = zeros(task_num, T);
    Data = zeros(task_num, T);
    
    % Safe retrieval of DNN_Data components
    get_comp = @(d, idx) d.comp;
    get_data = @(d, idx) d.data;
    
    if iscell(DNN_Data)
        get_comp = @(d, idx) d{idx}.comp;
        get_data = @(d, idx) d{idx}.data;
    elseif isstruct(DNN_Data) && numel(DNN_Data) > 1
        get_comp = @(d, idx) d(idx).comp;
        get_data = @(d, idx) d(idx).data;
    end
    
    for i = 1:task_num
        type = Task(i, 2);
        try
            if iscell(DNN_Data)
                if type > length(DNN_Data), type = 1; end
                c_vec = get_comp(DNN_Data, type);
                d_vec = get_data(DNN_Data, type);
            elseif isstruct(DNN_Data) && numel(DNN_Data) > 1
                if type > numel(DNN_Data), type = 1; end
                c_vec = get_comp(DNN_Data, type);
                d_vec = get_data(DNN_Data, type);
            else
                c_vec = DNN_Data.comp;
                d_vec = DNN_Data.data;
            end
            
            % Handle length mismatch
            len = length(c_vec);
            if len > T
                c_vec = c_vec(1:T);
                d_vec = d_vec(1:T);
            elseif len < T
                c_vec = [c_vec, zeros(1, T - len)];
                d_vec = [d_vec, zeros(1, T - len)];
            end
            
            Comp(i, :) = c_vec;
            Data(i, :) = d_vec;
        catch ME
             fprintf('Error building Pre struct for task %d (Type %d): %s\n', i, type, ME.message);
             Comp(i, :) = zeros(1, T);
             Data(i, :) = zeros(1, T);
        end
    end
    
    % --- 2. Channel & Rate ---
    noise_p = 1e-13;
    Rate = zeros(task_num, fog_num);
    
    for i = 1:task_num
        u_idx = Task(i, 4); % Thing ID
        tx_pow = Thing(u_idx, 6); % Power
        
        for f = 1:fog_num
            dist = sqrt(sum((Thing(u_idx, 1:2) - Fog(f, 1:2)).^2));
            dist = max(dist, 1.0); % Avoid singularity
            
            % Path Loss (Log-Distance Model)
            pl = 10^(-(28.46 + 20*log10(dist))/10);
            
            % Shannon Rate
            snr = tx_pow * pl * 0.5 / noise_p;
            bw = Fog(f, 6);
            Rate(i, f) = bw * log2(1 + snr);
        end
    end
    
    % --- 3. Latency Components ---
    Local_Speed = zeros(task_num, 1);
    for i=1:task_num
        u_idx = Task(i, 4);
        if size(Thing, 2) >= 4 && Thing(u_idx, 4) > 0.1
            Local_Speed(i) = Thing(u_idx, 4); 
        else
            Local_Speed(i) = Thing(u_idx, 3);
        end
        if Local_Speed(i) < 0.1, Local_Speed(i) = 1.0; end 
    end
    
    Local_Lat = bsxfun(@rdivide, Comp, Local_Speed);
    
    Trans = zeros(task_num, T, fog_num);
    for f = 1:fog_num
        r_f = Rate(:, f);
        r_f(r_f < 1e3) = 1e3; % Min rate
        Trans(:, :, f) = bsxfun(@rdivide, Data, r_f);
    end
    
    % --- 4. Expansion for Vectorization ---
    Comp_Exp = repmat(Comp, [1, 1, fog_num]);
    Data_Exp = repmat(Data, [1, 1, fog_num]);
    
    % --- 5. Deadlines ---
    Deadline = Task(:, 5);
    if size(Task, 2) >= 6 && any(Task(:, 6) > 0)
        Tolerance = Task(:, 6);
    else
        Tolerance = Deadline; % Default: Deadline is the hard limit
    end
    
    Pre.Comp = Comp;
    Pre.Comp_Matrix = Comp; % Alias for compatibility with Greedy/Lite solvers
    Pre.Data = Data;
    Pre.Data_Matrix = Data; % Alias for compatibility
    Pre.Comp_Exp = Comp_Exp;
    Pre.Data_Exp = Data_Exp;
    Pre.Local_Lat = Local_Lat;
    Pre.Trans = Trans;
    
    % Correct Logic for Satisfaction Function
    % Sat = 100 if Delay <= ET (Preferred)
    % Sat = 0 if Delay >= LT (Hard Limit)
    % Task(:, 5) is the generated Deadline, treat it as LT (Hard Limit).
    
    Pre.Deadline = Deadline;
    Pre.Tolerance = Tolerance;
    Pre.Task_Deadline = Tolerance; % LT
    Pre.Task_ET = Tolerance * 0.7; % ET (70% of Deadline is preferred)
    
    % Store Speeds for Debugging
    Pre.Local_Speed = Local_Speed;
    Pre.Fog_Speed = Fog(:, 7); % Service Rate
    Pre.Fog_BW = Fog(:, 6);    % Bandwidth
    
    % --- 6. Trace-Driven Latency Injection (Global Override) ---
    global GLOBAL_TRACE_DATA;
    if ~isempty(GLOBAL_TRACE_DATA)
        % Use the strictly sampled trace data from Main Experiment
        Pre.Trace_Comp_Matrix = GLOBAL_TRACE_DATA;
        Pre.Proc_Time_Trace = GLOBAL_TRACE_DATA(:, :, 1:fog_num);
    else
        % --- 6. Trace-Driven Latency Injection (Legacy/Local Load) ---
        % Reviewer Response: Inject real hardware traces (Cold/Hot Start)
        
        Pre.Proc_Time_Trace = []; 
        
        trace_dir = 'e:\postgraduate\first year\移动边缘计算\DNN_Hardware_Profiled_Simulation';
    jetson_csv = fullfile(trace_dir, 'Jetson_Nano_latency_log.csv');
    pi_csv = fullfile(trace_dir, 'Raspberry_Pi_4B_latency_log.csv');
    
    if exist(jetson_csv, 'file') && exist(pi_csv, 'file')
        try
            opts = detectImportOptions(jetson_csv);
            opts.VariableNamingRule = 'preserve';
            T_jetson = readtable(jetson_csv, opts);
            
            opts = detectImportOptions(pi_csv);
            opts.VariableNamingRule = 'preserve';
            T_pi = readtable(pi_csv, opts);
            
            Proc_Time_Trace = zeros(task_num, T, fog_num);
            model_map = {'vgg16', 'resnet50', 'mobilenet_v2'};
            
            for i = 1:task_num
                type_idx = Task(i, 2);
                if type_idx > 3, type_idx = 3; end 
                model_name = model_map{type_idx};
                
                rows_j = strcmp(T_jetson.Model, model_name);
                sub_j = T_jetson(rows_j, :);
                
                rows_p = strcmp(T_pi.Model, model_name);
                sub_p = T_pi(rows_p, :);
                
                c_vec = Comp(i, :);
                total_comp = sum(c_vec);
                if total_comp == 0, layer_ratios = zeros(1, T);
                else, layer_ratios = c_vec / total_comp;
                end
                
                for f = 1:fog_num
                    cap = Fog(f, 4); 
                    bw = Fog(f, 6);
                    
                    if cap > 20.0
                        % CLOUD
                        speed = Fog(f, 4); 
                        Proc_Time_Trace(i, :, f) = c_vec / speed;
                        
                    elseif cap < 5.0 && bw >= 15.0
                        % JETSON NANO (GPU)
                        if ~isempty(sub_j)
                            idx = randi(height(sub_j));
                            lat_ms = sub_j.Latency_ms(idx);
                            lat_sec = lat_ms / 1000.0;
                            Proc_Time_Trace(i, :, f) = lat_sec * layer_ratios;
                        else
                             Proc_Time_Trace(i, :, f) = c_vec / Fog(f, 4);
                        end
                        
                    elseif cap < 5.0 && bw < 15.0
                        % RASPBERRY PI (CPU)
                        if ~isempty(sub_p)
                            idx = randi(height(sub_p));
                            lat_ms = sub_p.Latency_ms(idx);
                            lat_sec = lat_ms / 1000.0;
                            Proc_Time_Trace(i, :, f) = lat_sec * layer_ratios;
                        else
                             Proc_Time_Trace(i, :, f) = c_vec / Fog(f, 4);
                        end
                    else
                        % Default
                        Proc_Time_Trace(i, :, f) = c_vec / Fog(f, 4);
                    end
                end
            end
            
            Pre.Proc_Time_Trace = Proc_Time_Trace;
            
        catch ME
            fprintf('[Pre] Warning: Failed to load traces: %s. Using static models.\n', ME.message);
        end
    end
    end % End of Global Trace else block

    Pre.Fog_Speed = Fog(:, 4)';
    Pre.Fog_BW = Fog(:, 6)';
    Pre.Local_Speed = Local_Speed;
    Pre.B = bsxfun(@rdivide, Rate, Fog(:, 6)');
    Pre.Task_Deadline = Tolerance; 
    Pre.Task_ET = Deadline;       
    
    % [CRITICAL] Infer Node Types for Context Switching Logic
    % 1=Nano, 2=Pi, 3=Cloud
    % Consistent with generate_tier1_env_trace.m logic
    Pre.Node_Types = zeros(1, fog_num);
    for f = 1:fog_num
        cap = Fog(f, 4); 
        bw = Fog(f, 6);
        if cap > 20.0
            Pre.Node_Types(f) = 3; % Cloud
        elseif cap < 5.0 && bw >= 15.0
            Pre.Node_Types(f) = 1; % Nano
        elseif cap < 5.0 && bw < 15.0
            Pre.Node_Types(f) = 2; % Pi
        else
            Pre.Node_Types(f) = 1; % Default to Nano
        end
    end
end
