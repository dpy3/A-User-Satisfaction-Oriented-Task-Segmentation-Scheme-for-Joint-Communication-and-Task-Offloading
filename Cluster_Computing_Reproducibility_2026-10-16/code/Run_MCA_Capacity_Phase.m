function Run_MCA_Capacity_Phase(mode, run_indices, profile_filter, load_filter)
% Stateful replay over frozen infrastructure profiles and normalized loads.
if nargin < 1 || isempty(mode), mode = 'capacityphasesmoke'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'capacityphase'), 'MCA:WrongMode', ...
    'Capacity-phase runner requires a capacityphase mode.');
if nargin < 2 || isempty(run_indices), run_indices = cfg.required_replay_runs; end
profiles = string(cfg.infrastructure_profiles);
if nargin >= 3 && ~isempty(profile_filter)
    profiles = intersect(profiles, string(profile_filter), 'stable');
end
loads = cfg.normalized_loads;
if nargin >= 4 && ~isempty(load_filter)
    loads = intersect(loads, load_filter, 'stable');
end
assert(~isempty(profiles) && ~isempty(loads), 'MCA:CapacityPhaseEmptyFilter', ...
    'No capacity-phase cell selected.');

capacity_root = cfg.results_root;
if isfield(cfg, 'capacity_reference_mode')
    capacity_cfg = MCA_Official_Config(cfg.capacity_reference_mode);
    capacity_root = capacity_cfg.results_root;
end
capacity_path = fullfile(capacity_root, 'Capacity_Reference_Frozen.csv');
assert(exist(capacity_path, 'file') == 2, 'MCA:CapacityReferenceMissing', ...
    'Run capacity calibration first: %s', capacity_path);
capacity_tbl = readtable(capacity_path, 'TextType', 'string');
assert(all(ismember(profiles, capacity_tbl.Profile)), 'MCA:CapacityReferenceProfile', ...
    'A selected profile lacks a frozen capacity reference.');
MCA_Write_Manifest(cfg, {mfilename('fullpath'), ...
    fullfile(fileparts(mfilename('fullpath')), 'MCA_Apply_Infrastructure_Profile.m'), ...
    fullfile(fileparts(mfilename('fullpath')), 'Validate_MCA_Capacity_Phase.m')});

slot_rows = repmat(slot_template(), 0, 1);
suffix = phase_suffix(profiles, loads, run_indices);
checkpoint = fullfile(cfg.results_root, ['CapacityPhase_Checkpoint_' suffix '.mat']);
checkpoint_state = struct(); checkpoint_key = ""; checkpoint_slot = 0;
if exist(checkpoint, 'file')
    saved = load(checkpoint);
    slot_rows = saved.slot_rows;
    checkpoint_state = saved.checkpoint_state;
    checkpoint_key = saved.checkpoint_key;
    checkpoint_slot = saved.checkpoint_slot;
    fprintf('Resuming %s from %d saved slot rows.\n', suffix, numel(slot_rows));
end

fprintf('MCA capacity phase %s: profiles=%s loads=%s runs=%s slots=%d\n', ...
    upper(cfg.mode), strjoin(profiles, ','), mat2str(loads), mat2str(run_indices), cfg.replay_slots);
for p = 1:numel(profiles)
    profile = profiles(p);
    ref_row = capacity_tbl(capacity_tbl.Profile == profile, :);
    assert(height(ref_row) == 1, 'MCA:CapacityReferenceDuplicate', ...
        'Profile %s does not have exactly one capacity reference.', profile);
    capacity_ref = ref_row.CapacityRef(1);
    profile_idx = find(string(cfg.infrastructure_profiles) == profile, 1);
    for load_idx = 1:numel(loads)
        lambda = loads(load_idx);
        N = max(1, round(capacity_ref * lambda));
        for run = run_indices
            cell_key = sprintf('%s/L%.6f/R%d', profile, lambda, run);
            completed_slots = completed_slot_count(slot_rows, profile, lambda, run, cfg.algorithms);
            if completed_slots == cfg.replay_slots
                fprintf('Skipping complete %s.\n', cell_key);
                continue;
            elseif completed_slots > 0
                assert(checkpoint_key == string(cell_key) && checkpoint_slot == completed_slots, ...
                    'MCA:CapacityPhaseResumeState', 'Checkpoint state mismatch for %s.', cell_key);
                state = checkpoint_state;
            else
                state = initialize_state(cfg.algorithms);
            end
            for slot = (completed_slots + 1):cfg.replay_slots
                env_seed = cfg.seed_base + 100000000 * profile_idx + ...
                    1000000 * load_idx + 1000 * run + slot;
                rng(env_seed, 'twister');
                [arr_task, Fog, arr_thing, DNN_Data] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
                [Fog, profile_meta] = MCA_Apply_Infrastructure_Profile(Fog, profile);
                for a = 1:numel(cfg.algorithms)
                    alg = cfg.algorithms{a};
                    pending = state.(alg);
                    Task = [pending.Task; arr_task];
                    Thing = [pending.Thing; arr_thing];
                    Task(:, 1) = (1:size(Task, 1))';
                    Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
                    Pre.Mean_Deadline = mean(Task(:, 3));
                    Pre.Violation_Mode = cfg.violation_mode;
                    Pre.BacklogIn = size(pending.Task, 1);
                    Pre.Arrivals = size(arr_task, 1);
                    Pre.ReplayScaleN = N;
                    Pre.FullBacklogStreak = pending.FullBacklogStreak;
                    rng(env_seed + 1000 * a, 'twister');
                    t0 = tic;
                    theta = MCA_Solve(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
                    runtime = toc(t0);
                    m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
                        sprintf('capacity-phase/%s/L%.3f/R%d/S%d/%s', profile, lambda, run, slot, alg));
                    unresolved = m.SatisfiedVector < 0.5;
                    backlog_before_cap = sum(unresolved);
                    cap = round(cfg.replay_backlog_cap_ratio * N);
                    keep_count = min(backlog_before_cap, cap);
                    if keep_count == 0
                        keep = zeros(0, 1);
                    else
                        keep = find(unresolved, keep_count, 'first');
                    end
                    state.(alg).Task = Task(keep, :);
                    state.(alg).Thing = Thing(keep, :);
                    if keep_count >= cap && cap > 0
                        state.(alg).FullBacklogStreak = Pre.FullBacklogStreak + 1;
                    else
                        state.(alg).FullBacklogStreak = 0;
                    end
                    cap_drop = max(0, backlog_before_cap - cap);
                    slot_rows(end + 1) = make_slot(cfg, profile, lambda, capacity_ref, N, ...
                        run, slot, env_seed, alg, size(pending.Task, 1), size(arr_task, 1), ...
                        numel(keep), cap_drop, runtime, m, profile_meta); %#ok<AGROW>
                end
                checkpoint_state = state;
                checkpoint_key = string(cell_key);
                checkpoint_slot = slot;
                save_checkpoint_atomic(checkpoint, slot_rows, cfg, profiles, loads, run_indices, ...
                    checkpoint_state, checkpoint_key, checkpoint_slot);
            end
        end
    end
end

slot_tbl = struct2table(slot_rows);
run_rows = repmat(run_template(), 0, 1);
for p = 1:numel(profiles)
    for load_idx = 1:numel(loads)
        for run = run_indices
            for a = 1:numel(cfg.algorithms)
                alg = string(cfg.algorithms{a});
                mask = slot_tbl.Profile == profiles(p) & ...
                    abs(slot_tbl.NormalizedLoadTarget - loads(load_idx)) < 1e-12 & ...
                    slot_tbl.Run == run & slot_tbl.Algorithm == alg;
                run_rows(end + 1) = make_run(cfg, slot_tbl(mask, :)); %#ok<AGROW>
            end
        end
    end
end
run_tbl = struct2table(run_rows);
writetable(slot_tbl, fullfile(cfg.results_root, ['CapacityPhase_SlotLevel_' suffix '.csv']));
writetable(run_tbl, fullfile(cfg.results_root, ['CapacityPhase_RunLevel_' suffix '.csv']));
save(fullfile(cfg.results_root, ['CapacityPhase_Results_' suffix '.mat']), 'slot_tbl', 'run_tbl', 'cfg');
Validate_MCA_Capacity_Phase(slot_tbl, run_tbl, cfg, false);
fprintf('CAPACITY PHASE %s PASS: %d slot rows, %d run rows.\n', ...
    upper(cfg.mode), height(slot_tbl), height(run_tbl));
end

function save_checkpoint_atomic(checkpoint, slot_rows, cfg, profiles, loads, run_indices, ...
        checkpoint_state, checkpoint_key, checkpoint_slot)
tmp = [checkpoint '.tmp'];
save(tmp, 'slot_rows', 'cfg', 'profiles', 'loads', 'run_indices', ...
    'checkpoint_state', 'checkpoint_key', 'checkpoint_slot');
ok = false; msg = '';
for attempt = 1:20
    [ok, msg] = movefile(tmp, checkpoint, 'f');
    if ok, break; end
    pause(0.1 * attempt);
end
if ~ok
    warning('MCA:CapacityPhaseCheckpoint', 'Could not commit checkpoint: %s', msg);
    if exist(tmp, 'file'), delete(tmp); end
end
end

function count = completed_slot_count(rows, profile, lambda, run, algorithms)
if isempty(rows), count = 0; return; end
names = string({rows.Algorithm});
profiles = string({rows.Profile});
loads = [rows.NormalizedLoadTarget];
counts = zeros(numel(algorithms), 1);
for a = 1:numel(algorithms)
    counts(a) = sum(profiles == profile & abs(loads - lambda) < 1e-12 & ...
        [rows.Run] == run & names == string(algorithms{a}));
end
assert(all(counts == counts(1)), 'MCA:CapacityPhasePartialPair', ...
    'Algorithms have unequal completed slot counts.');
count = counts(1);
end

function state = initialize_state(algorithms)
state = struct();
for i = 1:numel(algorithms)
    state.(algorithms{i}) = struct('Task', zeros(0, 6), 'Thing', zeros(0, 6), ...
        'FullBacklogStreak', 0);
end
end

function suffix = phase_suffix(profiles, loads, runs)
if numel(profiles) == 1, p = char(profiles(1)); else, p = sprintf('P%d', numel(profiles)); end
if numel(loads) == 1, l = sprintf('L%03d', round(loads(1) * 100)); else, l = sprintf('L%d', numel(loads)); end
suffix = sprintf('%s_%s_R%dto%d', p, l, runs(1), runs(end));
end

function row = slot_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'Profile', "", ...
    'NormalizedLoadTarget', 0, 'CapacityRef', 0, 'RealizedNormalizedLoad', 0, ...
    'N', 0, 'Run', 0, 'Slot', 0, 'EnvironmentSeed', 0, 'Algorithm', "", ...
    'BacklogIn', 0, 'Arrivals', 0, 'OfferedTasks', 0, 'SatisfiedCount', 0, ...
    'Sat', 0, 'Admission', 0, 'ResourceViolation', 0, 'CompositeViolation', 0, ...
    'BacklogOut', 0, 'BacklogRatioIn', 0, 'FullBacklogStreakIn', 0, ...
    'OverloadModeActive', false, 'DroppedByQueueCap', 0, 'DeadlineMissCount', 0, ...
    'MemoryBlockCount', 0, 'IntrinsicLatencyBlockCount', 0, 'SpilloverBlockCount', 0, ...
    'FeasibleMissedCount', 0, 'RuntimeSec', 0, 'TotalCompute', 0, ...
    'TotalMemoryMB', 0, 'TotalBandwidthMbps', 0);
end

function row = make_slot(cfg, profile, lambda, capacity_ref, N, run, slot, seed, alg, ...
        backlog_in, arrivals, backlog_out, cap_drop, runtime, m, meta)
row = slot_template();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.Profile = profile; row.NormalizedLoadTarget = lambda; row.CapacityRef = capacity_ref;
row.RealizedNormalizedLoad = N / capacity_ref; row.N = N; row.Run = run; row.Slot = slot;
row.EnvironmentSeed = seed; row.Algorithm = string(alg); row.BacklogIn = backlog_in;
row.Arrivals = arrivals; row.OfferedTasks = m.TaskCount; row.SatisfiedCount = m.SatisfiedCount;
row.Sat = m.Sat; row.Admission = m.Admission; row.ResourceViolation = m.ResourceViolation;
row.CompositeViolation = m.CompositeViolation; row.BacklogOut = backlog_out;
row.BacklogRatioIn = backlog_in / max(1, N); row.DroppedByQueueCap = cap_drop;
row.FullBacklogStreakIn = m.FullBacklogStreakIn; row.OverloadModeActive = m.OverloadModeActive;
row.DeadlineMissCount = m.DeadlineMissCount; row.MemoryBlockCount = m.MemoryBlockCount;
row.IntrinsicLatencyBlockCount = m.IntrinsicLatencyBlockCount;
row.SpilloverBlockCount = m.SpilloverBlockCount; row.FeasibleMissedCount = m.FeasibleMissedCount;
row.RuntimeSec = runtime; row.TotalCompute = meta.TotalCompute;
row.TotalMemoryMB = meta.TotalMemoryMB; row.TotalBandwidthMbps = meta.TotalBandwidthMbps;
end

function row = run_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'Profile', "", ...
    'NormalizedLoadTarget', 0, 'CapacityRef', 0, 'RealizedNormalizedLoad', 0, ...
    'N', 0, 'Run', 0, 'Algorithm', "", 'Slots', 0, 'MeanSat', 0, ...
    'TotalSatisfied', 0, 'BacklogAUC', 0, 'PeakBacklog', 0, 'FinalBacklog', 0, ...
    'QueueCapDrops', 0, 'DeadlineMisses', 0, 'MemoryBlocks', 0, ...
    'IntrinsicLatencyBlocks', 0, 'SpilloverBlocks', 0, 'FeasibleMisses', 0, ...
    'MeanRuntimeSec', 0);
end

function row = make_run(cfg, block)
assert(height(block) > 0, 'MCA:CapacityPhaseRunEmpty', 'Cannot summarize an empty run.');
row = run_template();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.Profile = block.Profile(1); row.NormalizedLoadTarget = block.NormalizedLoadTarget(1);
row.CapacityRef = block.CapacityRef(1); row.RealizedNormalizedLoad = block.RealizedNormalizedLoad(1);
row.N = block.N(1); row.Run = block.Run(1); row.Algorithm = block.Algorithm(1);
row.Slots = height(block); row.MeanSat = mean(block.Sat);
row.TotalSatisfied = sum(block.SatisfiedCount); row.BacklogAUC = sum(block.BacklogOut);
row.PeakBacklog = max(block.BacklogOut); row.FinalBacklog = block.BacklogOut(end);
row.QueueCapDrops = sum(block.DroppedByQueueCap); row.DeadlineMisses = sum(block.DeadlineMissCount);
row.MemoryBlocks = sum(block.MemoryBlockCount);
row.IntrinsicLatencyBlocks = sum(block.IntrinsicLatencyBlockCount);
row.SpilloverBlocks = sum(block.SpilloverBlockCount); row.FeasibleMisses = sum(block.FeasibleMissedCount);
row.MeanRuntimeSec = mean(block.RuntimeSec);
end
