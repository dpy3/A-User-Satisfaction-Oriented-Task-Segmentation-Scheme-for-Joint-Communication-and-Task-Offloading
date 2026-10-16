function manifest_path = MCA_Write_Manifest(cfg, extra_files)
if nargin < 2, extra_files = {}; end
core = { ...
    fullfile(cfg.code_root, 'Utils', 'MCA_Selection_Score.m'), ...
    fullfile(cfg.code_root, 'MCA_Solve.m'), ...
    fullfile(cfg.code_root, 'MCA_Evaluate.m'), ...
    fullfile(cfg.code_root, 'MCA_Official_Config.m'), ...
    fullfile(cfg.code_root, 'Data', 'Hardware_Profile_Data.m'), ...
    fullfile(cfg.code_root, 'Utils', 'calculate_metrics_v2.m'), ...
    fullfile(cfg.code_root, 'Utils', 'Perform_Safe_Harbor_Repair.m'), ...
    fullfile(cfg.code_root, 'Utils', 'Perform_Global_Optimization.m'), ...
    fullfile(cfg.code_root, 'Environment', 'generate_tier1_env_trace.m'), ...
    fullfile(cfg.code_root, 'Environment', 'build_pre_struct_tier1.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'Greedy_Solver_DNN.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'GA_Solver_DNN_Vectorized.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'M_CA_ALM_Solver.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'LP_Relaxed_Solver_Binary.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'DPP_Solver_Binary.m'), ...
    fullfile(cfg.code_root, 'Algorithms', 'MPC_Rollout_Solver_Binary.m')};
files = unique([core(:); extra_files(:)], 'stable');
sha = strings(numel(files), 1);
bytes = zeros(numel(files), 1);
for i = 1:numel(files)
    physical_file = java.io.File(files{i});
    if ~physical_file.isFile() && java.io.File([files{i} '.m']).isFile()
        files{i} = [files{i} '.m'];
    end
    assert(java.io.File(files{i}).isFile(), 'MCA:ManifestMissingFile', 'Missing file: %s', files{i});
    file_obj = java.io.File(files{i});
    bytes(i) = file_obj.length();
    sha(i) = sha256_file(files{i});
end
manifest = table(string(files), sha, bytes, 'VariableNames', {'File', 'SHA256', 'Bytes'});
manifest_path = fullfile(cfg.results_root, 'CODE_MANIFEST_SHA256.csv');
% Keep defective historical records; new hashes attest the current snapshot.
if exist(manifest_path, 'file')
    manifest_path = fullfile(cfg.results_root, 'CODE_MANIFEST_CURRENT_SNAPSHOT_SHA256.csv');
end
if exist(manifest_path, 'file')
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    manifest_path = fullfile(cfg.results_root, ['CODE_MANIFEST_CURRENT_SNAPSHOT_' stamp '_SHA256.csv']);
end
writetable(manifest, manifest_path);
config_path = fullfile(cfg.results_root, 'FROZEN_CONFIG.mat');
if exist(config_path, 'file')
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    config_path = fullfile(cfg.results_root, ['CURRENT_CONFIG_SNAPSHOT_' stamp '.mat']);
end
save(config_path, 'cfg');
end

function value = sha256_file(path_value)
fid = fopen(path_value, 'rb');
assert(fid >= 0, 'MCA:HashRead', 'Cannot read file: %s', path_value);
cleanup = onCleanup(@() fclose(fid));
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    buffer = fread(fid, 65536, '*uint8');
    if isempty(buffer), break; end
    digest.update(typecast(buffer(:), 'int8'));
end
raw = typecast(digest.digest(), 'uint8');
value = lower(reshape(dec2hex(raw, 2)', 1, []));
end
