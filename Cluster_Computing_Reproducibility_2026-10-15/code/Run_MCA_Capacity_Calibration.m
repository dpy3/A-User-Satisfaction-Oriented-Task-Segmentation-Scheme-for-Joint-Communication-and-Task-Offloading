function Run_MCA_Capacity_Calibration(mode)
% Calibrate a policy-independent load denominator from simulator constraints.
if nargin < 1 || isempty(mode), mode = 'capacityphasesmoke'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'capacityphase'), 'MCA:WrongMode', ...
    'Capacity calibration requires a capacityphase mode.');
MCA_Write_Manifest(cfg, {mfilename('fullpath'), ...
    fullfile(fileparts(mfilename('fullpath')), 'MCA_Apply_Infrastructure_Profile.m')});

rows = repmat(probe_template(), 0, 1);
for p = 1:numel(cfg.infrastructure_profiles)
    profile = cfg.infrastructure_profiles{p};
    for run = cfg.capacity_calibration_runs
        % Profiles share the same task, position, and channel draws within a run.
        seed = cfg.seed_base + 1000 * run;
        rng(seed, 'twister');
        N = cfg.capacity_calibration_sample_size;
        [Task, Fog, Thing, DNN_Data] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
        [Fog, meta] = MCA_Apply_Infrastructure_Profile(Fog, profile);
        Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
        [capacity, diag] = estimate_capacity_lp(Task, Fog, DNN_Data, Pre);
        row = probe_template();
        row.SchemaVersion = string(cfg.schema_version);
        row.Profile = string(profile);
        row.SampleN = N;
        row.Run = run;
        row.Seed = seed;
        row.CapacityEstimate = capacity;
        row.LatencyExcludedPairs = diag.LatencyExcludedPairs;
        row.ActiveComputeNodes = diag.ActiveComputeNodes;
        row.ActiveMemoryNodes = diag.ActiveMemoryNodes;
        row.TotalCompute = meta.TotalCompute;
        row.TotalMemoryMB = meta.TotalMemoryMB;
        row.TotalBandwidthMbps = meta.TotalBandwidthMbps;
        rows(end + 1) = row; %#ok<AGROW>
    end
end

probe_tbl = struct2table(rows);
summary_rows = repmat(summary_template(), 0, 1);
for p = 1:numel(cfg.infrastructure_profiles)
    profile = string(cfg.infrastructure_profiles{p});
    block = probe_tbl(probe_tbl.Profile == profile, :);
    capacity_ref = median(block.CapacityEstimate);
    row = summary_template();
    row.SchemaVersion = string(cfg.schema_version);
    row.Profile = profile;
    row.CapacityRef = max(1, round(capacity_ref));
    row.MinCapacityEstimate = min(block.CapacityEstimate);
    row.MaxCapacityEstimate = max(block.CapacityEstimate);
    row.CalibrationRuns = numel(cfg.capacity_calibration_runs);
    row.CalibrationSampleN = cfg.capacity_calibration_sample_size;
    row.LatencyExcludedPairs = round(median(block.LatencyExcludedPairs));
    row.ActiveComputeNodes = round(median(block.ActiveComputeNodes));
    row.ActiveMemoryNodes = round(median(block.ActiveMemoryNodes));
    row.TotalCompute = block.TotalCompute(1);
    row.TotalMemoryMB = block.TotalMemoryMB(1);
    row.TotalBandwidthMbps = block.TotalBandwidthMbps(1);
    summary_rows(end + 1) = row; %#ok<AGROW>
end
summary_tbl = struct2table(summary_rows);

writetable(probe_tbl, fullfile(cfg.results_root, 'Capacity_Calibration_LP.csv'));
writetable(summary_tbl, fullfile(cfg.results_root, 'Capacity_Reference_Frozen.csv'));
save(fullfile(cfg.results_root, 'Capacity_Calibration.mat'), 'probe_tbl', 'summary_tbl', 'cfg');
fprintf('CAPACITY CALIBRATION %s PASS: %d probe rows, %d frozen profiles.\n', ...
    upper(cfg.mode), height(probe_tbl), height(summary_tbl));
disp(summary_tbl);
end

function row = probe_template()
row = struct('SchemaVersion', "", 'Profile', "", 'SampleN', 0, 'Run', 0, ...
    'Seed', 0, 'CapacityEstimate', 0, 'LatencyExcludedPairs', 0, ...
    'ActiveComputeNodes', 0, 'ActiveMemoryNodes', 0, 'TotalCompute', 0, ...
    'TotalMemoryMB', 0, 'TotalBandwidthMbps', 0);
end

function row = summary_template()
row = struct('SchemaVersion', "", 'Profile', "", 'CapacityRef', 0, ...
    'MinCapacityEstimate', 0, 'MaxCapacityEstimate', 0, 'CalibrationRuns', 0, ...
    'CalibrationSampleN', 0, 'LatencyExcludedPairs', 0, ...
    'ActiveComputeNodes', 0, 'ActiveMemoryNodes', 0, 'TotalCompute', 0, ...
    'TotalMemoryMB', 0, 'TotalBandwidthMbps', 0);
end

function [capacity, diag] = estimate_capacity_lp(Task, Fog, DNN_Data, Pre)
% Maximize a composition-preserving admitted batch under the same compute,
% memory, and intrinsic-latency constraints used by the simulator.
M = size(Fog, 1);
T = 3;
mix = [0.4; 0.3; 0.3];
mean_deadline = mean(Task(:, 3));
comp = zeros(T, M);
comm = zeros(T, M);
deadline = zeros(T, 1);
mem = zeros(T, 1);
for t = 1:T
    mask = Task(:, 2) == t;
    assert(any(mask), 'MCA:CapacitySampleMix', 'Calibration sample lacks task type %d.', t);
    comp(t, :) = mean(Pre.Comp(mask, :), 1);
    comm(t, :) = mean(Pre.Comm(mask, :), 1);
    deadline(t) = mean(Task(mask, 3));
    mem(t) = task_memory_mb(t, DNN_Data);
end

vars = T * M + 1;
k_idx = vars;
f = zeros(vars, 1);
f(k_idx) = -1;
Aeq = zeros(T, vars);
for t = 1:T
    Aeq(t, (t - 1) * M + (1:M)) = 1;
    Aeq(t, k_idx) = -mix(t);
end
beq = zeros(T, 1);
A = zeros(2 * M, vars);
b = zeros(2 * M, 1);
for node = 1:M
    for t = 1:T
        idx = (t - 1) * M + node;
        A(node, idx) = comp(t, node);
        A(M + node, idx) = mem(t);
    end
    b(node) = 0.99 * mean_deadline;
    b(M + node) = Fog(node, 8);
end
lb = zeros(vars, 1);
ub = inf(vars, 1);
for t = 1:T
    for node = 1:M
        if comm(t, node) + comp(t, node) > deadline(t)
            ub((t - 1) * M + node) = 0;
        end
    end
end
options = optimoptions('linprog', 'Display', 'none');
[x, ~, exitflag] = linprog(f, A, b, Aeq, beq, lb, ub, options);
assert(exitflag > 0 && ~isempty(x), 'MCA:CapacityLP', 'Capacity LP failed with exitflag %d.', exitflag);
capacity = x(k_idx);
compute_util = (A(1:M, :) * x) ./ max(b(1:M), 1e-12);
memory_util = (A(M + (1:M), :) * x) ./ max(b(M + (1:M)), 1e-12);
diag = struct('LatencyExcludedPairs', sum(ub(1:T * M) == 0), ...
    'ActiveComputeNodes', sum(compute_util >= 1 - 1e-6), ...
    'ActiveMemoryNodes', sum(memory_util >= 1 - 1e-6));
end

function mem_mb = task_memory_mb(t_type, DNN_Data)
if isnumeric(DNN_Data)
    row_idx = 4 - t_type;
    mem_mb = DNN_Data(row_idx, 1) + DNN_Data(row_idx, 2);
elseif iscell(DNN_Data)
    model = DNN_Data{t_type};
    mem_mb = sum(model.data);
else
    model = DNN_Data(t_type);
    mem_mb = sum(model.data);
end
end
