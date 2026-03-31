function theta_bin = Neurosurgeon_Solver(Task, Fog, Thing, DNN_Data)
    % Neurosurgeon: Optimize each task independently, ignoring interference.
    % Calculates Local vs Remote latency (assuming no congestion) and picks min.
    
    [task_num, ~] = size(Task);
    [fog_num, ~] = size(Fog);
    
    if iscell(DNN_Data)
        T = length(DNN_Data{1}.comp);
    else
        T = length(DNN_Data.comp);
    end
    
    theta_bin = zeros(task_num, T, fog_num);
    
    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
    
    for n = 1:task_num
        local_lat = Pre.Local_Lat(n);
        
        best_remote_lat = inf;
        best_f = -1;
        
        for f = 1:fog_num
            % Transmission + Computation (No Queueing)
            trans_lat = Pre.Trans(n, 1, f); % Assume T=1 or avg
            comp_lat = Pre.Comp_Exp(n, 1, f) / Pre.Fog_Speed(f);
            
            total_remote = trans_lat + comp_lat;
            
            if total_remote < best_remote_lat
                best_remote_lat = total_remote;
                best_f = f;
            end
        end
        
        if best_remote_lat < local_lat
            theta_bin(n, :, best_f) = 1;
        else
            % Local (all zeros)
        end
    end
end
