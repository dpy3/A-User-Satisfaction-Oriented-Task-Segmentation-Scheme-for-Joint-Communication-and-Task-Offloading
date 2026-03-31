function theta_bin = run_cloud(Task, Fog, Thing, DNN_Data)
    [task_num, ~] = size(Task);
    [fog_num, ~] = size(Fog);
    
    if iscell(DNN_Data)
        T = length(DNN_Data{1}.comp);
    else
        T = length(DNN_Data.comp);
    end
    
    theta_bin = zeros(task_num, T, fog_num);
    
    % Offload all to Fog 1 (or spread evenly?)
    % Usually "Cloud Only" means force offload.
    % We'll distribute round-robin to avoid instant overload if possible, 
    % or just random.
    % To be fair, let's pick Random Fog.
    
    for n = 1:task_num
        for t = 1:T
            f_idx = randi(fog_num);
            theta_bin(n, t, f_idx) = 1;
        end
    end
end
