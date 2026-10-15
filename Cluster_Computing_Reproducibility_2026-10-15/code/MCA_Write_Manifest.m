function manifest_path = MCA_Write_Manifest(cfg, extra_files)
if nargin < 2, extra_files = {}; end
core = { ...
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
writetable(manifest, manifest_path);
save(fullfile(cfg.results_root, 'FROZEN_CONFIG.mat'), 'cfg');
end

function value = sha256_file(path_value)
stream = java.io.FileInputStream(java.io.File(path_value));
cleanup = onCleanup(@() stream.close());
digest = java.security.MessageDigest.getInstance('SHA-256');
buffer = zeros(1, 65536, 'int8');
while true
    n = stream.read(buffer, 0, numel(buffer));
    if n < 0, break; end
    digest.update(buffer(1:n));
end
raw = typecast(digest.digest(), 'uint8');
value = lower(reshape(dec2hex(raw, 2)', 1, []));
end
