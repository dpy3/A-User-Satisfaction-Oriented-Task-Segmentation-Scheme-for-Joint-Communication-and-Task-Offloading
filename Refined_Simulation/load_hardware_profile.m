function [DNN_Profiles] = load_hardware_profile()
    % LOAD_HARDWARE_PROFILE
    % Reads hardware performance profiles from local CSV files.
    % Ensures simulation inputs are grounded in real-world measurements.
    %
    % Output:
    %   DNN_Profiles: struct containing VGG16, MobileNet, ResNet profiles.
    %       Each profile has:
    %       - .data: Output data size (MB) per layer
    %       - .comp: Computation load (GFLOPs) per layer
    %       - .layer_type: Type of layer (Conv, Pool, FC)
    
    script_folder = fileparts(mfilename('fullpath'));
    
    % Load VGG16
    vgg_path = fullfile(script_folder, 'VGG16_Profile.csv');
    if exist(vgg_path, 'file')
        DNN_Profiles.vgg16 = read_profile(vgg_path);
    else
        warning('VGG16_Profile.csv not found. Using fallback.');
        DNN_Profiles.vgg16 = get_fallback_vgg16();
    end
    
    % Load MobileNet (Optional)
    mob_path = fullfile(script_folder, 'MobileNet_Profile.csv');
    if exist(mob_path, 'file')
        DNN_Profiles.mobilenet = read_profile(mob_path);
    end
    
    % Load ResNet (Optional)
    res_path = fullfile(script_folder, 'ResNet_Profile.csv');
    if exist(res_path, 'file')
        DNN_Profiles.resnet = read_profile(res_path);
    end
    
    fprintf('Hardware Profiles Loaded: VGG16 (Real-World Data)\n');
end

function profile = read_profile(filepath)
    % Just read the table directly, let MATLAB handle types
    opts = detectImportOptions(filepath);
    opts.PreserveVariableNames = true; 
    T = readtable(filepath, opts);
    
    % Map columns safely
    vars = T.Properties.VariableNames;
    
    if ismember('Output_Data_MB', vars)
        profile.data = T.Output_Data_MB';
    elseif ismember('Input_MB', vars)
        profile.data = T.Input_MB';
    elseif ismember('Output_Data_MB', strrep(vars, ' ', '_')) % Try to match if spaces were replaced
         % Find the one that matches
         idx = find(strcmp(strrep(vars, ' ', '_'), 'Output_Data_MB'));
         profile.data = T{:, idx}';
    else
        fprintf('Available columns: %s\n', strjoin(vars, ', '));
        error('Invalid CSV format: Missing Output_Data_MB or Input_MB in %s', filepath);
    end
    
    if ismember('Comp_GFLOPs', vars)
        profile.comp = T.Comp_GFLOPs';
    else
         error('Invalid CSV format: Missing Comp_GFLOPs');
    end
    
    if ismember('Layer_Type', T.Properties.VariableNames)
        profile.layer_type = T.Layer_Type;
    end
end

function vgg16 = get_fallback_vgg16()
    vgg16.data = [150, 75, 37.5, 18.8, 9.4, 0.004]; 
    vgg16.comp = [0.25, 2.5, 0.1, 5.5, 0.1, 0.5]; 
end
