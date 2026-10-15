function Run_MCA_Repair_Transfer(mode, scale_indices, run_indices)
if nargin < 1 || isempty(mode), mode = 'repairtransfersmoke'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'repairtransfer'), 'MCA:WrongMode', ...
    'Repair-transfer runner requires a repair-transfer mode.');
if nargin < 2 || isempty(scale_indices), scale_indices = 1:numel(cfg.static_scales); end
if nargin < 3 || isempty(run_indices), run_indices = cfg.required_static_runs; end
assert(all(ismember(scale_indices, 1:numel(cfg.static_scales))), ...
    'MCA:ScaleIndex', 'Invalid scale index.');
assert(all(ismember(run_indices, cfg.required_static_runs)), ...
    'MCA:RunIndex', 'Run index is outside the frozen repair-transfer set.');

suffix = shard_suffix(scale_indices, run_indices, cfg);
checkpoint = fullfile(cfg.results_root, ['RepairTransfer_Checkpoint' suffix '.mat']);
output_path = fullfile(cfg.results_root, ['RepairTransfer_RunLevel' suffix '.csv']);
here = fileparts(mfilename('fullpath'));
MCA_Write_Manifest(cfg, {mfilename('fullpath'), which('MCA_Solve'), ...
    which('MCA_Official_Config'), which('Analyze_MCA_Repair_Transfer'), ...
    fullfile(here, 'REPAIR_TRANSFER_PROTOCOL.md')});

rows = repmat(base_row(), 0, 1);
if exist(checkpoint, 'file')
    saved = load(checkpoint, 'rows');
    rows = saved.rows;
end

fprintf('MCA repair transfer %s: scales=%s, runs=%s\n', upper(cfg.mode), ...
    mat2str(cfg.static_scales(scale_indices)), mat2str(run_indices));
for n_idx = scale_indices(:)'
    N = cfg.static_scales(n_idx);
    seed_idx = find(cfg.seed_scale_reference == N, 1);
    assert(~isempty(seed_idx), 'MCA:SeedScaleReference', ...
        'N=%d lacks a seed-scale reference.', N);
    for run = run_indices(:)'
        seed = cfg.seed_base + 100000 * seed_idx + run;
        if is_complete(rows, N, run, seed, cfg.algorithms), continue; end

        rng(seed, 'twister');
        [Task, Fog, Thing, DNN_Data, Pre] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
        Pre.Mean_Deadline = mean(Task(:, 3));
        Pre.Violation_Mode = cfg.violation_mode;
        rows = remove_partial(rows, N, run, seed);

        for a = 1:numel(cfg.algorithms)
            alg = cfg.algorithms{a};
            [family, repair_aware, stream_offset] = algorithm_factors(alg);
            % Raw and repair-aware arms receive identical random streams
            % within each optimizer family; only ranking semantics differ.
            rng(seed + stream_offset, 'twister');
            t0 = tic;
            theta = MCA_Solve(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
            runtime = toc(t0);
            m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
                sprintf('repair-transfer/N%d/R%d/%s', N, run, alg));
            assert(m.ResourceViolation == 0, 'MCA:PostRepairResourceViolation', ...
                'N=%d run=%d %s has post-repair resource violation.', N, run, alg);
            rows(end + 1) = make_row(cfg, N, run, seed, alg, family, ...
                repair_aware, runtime, m); %#ok<AGROW>
            fprintf('N=%d run=%d %s Sat=%.2f Runtime=%.3fs\n', ...
                N, run, alg, m.Sat, runtime);
        end
        save(checkpoint, 'rows', 'cfg', 'scale_indices', 'run_indices');
    end
end

tbl = struct2table(rows);
writetable(tbl, output_path);
Validate_MCA_Official_Results(output_path, cfg);
fprintf('REPAIR TRANSFER %s PASS: %s\n', upper(cfg.mode), output_path);
end

function [family, repair_aware, stream_offset] = algorithm_factors(alg)
name = upper(char(alg));
if startsWith(name, 'GAHYBRID')
    family = "GAHybrid";
    stream_offset = 2000;
elseif startsWith(name, 'ALM')
    family = "ALM";
    stream_offset = 3000;
else
    error('MCA:RepairTransferAlgorithm', 'Unexpected algorithm: %s', alg);
end
repair_aware = endsWith(name, 'REPAIRAWARE');
end

function tf = is_complete(rows, N, run, seed, algorithms)
if isempty(rows), tf = false; return; end
mask = [rows.N] == N & [rows.Run] == run & [rows.Seed] == seed;
names = sort(string({rows(mask).Algorithm}));
tf = isequal(names(:), sort(string(algorithms(:))));
end

function rows = remove_partial(rows, N, run, seed)
if isempty(rows), return; end
mask = [rows.N] == N & [rows.Run] == run & [rows.Seed] == seed;
rows(mask) = [];
end

function suffix = shard_suffix(scale_indices, run_indices, cfg)
full_scales = isequal(scale_indices(:)', 1:numel(cfg.static_scales));
full_runs = isequal(run_indices(:)', cfg.required_static_runs(:)');
if full_scales && full_runs
    suffix = '';
else
    suffix = sprintf('_S%s_R%s', strjoin(string(scale_indices), '-'), ...
        strjoin(string(run_indices), '-'));
end
end

function row = base_row()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, ...
    'FogNodes', 0, 'Run', 0, 'Seed', 0, 'Algorithm', "", ...
    'OptimizerFamily', "", 'RepairAwareRanking', false, 'Sat', 0, ...
    'Admission', 0, 'TimelyAmongAdmitted', 0, 'ResourceViolation', 0, ...
    'DeadlineViolation', 0, 'CompositeViolation', 0, 'InvalidAssignment', 0, ...
    'LatencyAdmitted', 0, 'LatencyTimely', 0, 'SatisfiedCount', 0, ...
    'AdmittedCount', 0, 'TaskCount', 0, 'RuntimeSec', 0);
end

function row = make_row(cfg, N, run, seed, alg, family, repair_aware, runtime, m)
row = base_row();
row.SchemaVersion = string(cfg.schema_version);
row.EvidenceClass = upper(string(cfg.mode));
row.N = N;
row.FogNodes = cfg.fog_num_fixed;
row.Run = run;
row.Seed = seed;
row.Algorithm = string(alg);
row.OptimizerFamily = family;
row.RepairAwareRanking = repair_aware;
fields = {'Sat','Admission','TimelyAmongAdmitted','ResourceViolation', ...
    'DeadlineViolation','CompositeViolation','InvalidAssignment', ...
    'LatencyAdmitted','LatencyTimely','SatisfiedCount','AdmittedCount','TaskCount'};
for i = 1:numel(fields), row.(fields{i}) = m.(fields{i}); end
row.RuntimeSec = runtime;
end
