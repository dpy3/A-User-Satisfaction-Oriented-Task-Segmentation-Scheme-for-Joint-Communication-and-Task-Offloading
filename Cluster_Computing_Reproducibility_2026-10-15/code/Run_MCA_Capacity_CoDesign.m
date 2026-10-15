function Run_MCA_Capacity_CoDesign(mode, run_indices, profile_filter, load_filter)
% Compare frozen selectors with explicit admission and elastic capacity actions.
if nargin < 1 || isempty(mode), mode = 'capacitycodesignsmoke'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'capacitycodesign'), 'MCA:WrongMode', ...
    'Co-design runner requires a capacitycodesign mode.');
if nargin < 2 || isempty(run_indices), run_indices = cfg.required_replay_runs; end
profiles = string(cfg.infrastructure_profiles);
if nargin >= 3 && ~isempty(profile_filter), profiles = intersect(profiles, string(profile_filter), 'stable'); end
loads = cfg.normalized_loads;
if nargin >= 4 && ~isempty(load_filter), loads = intersect(loads, load_filter, 'stable'); end
assert(~isempty(profiles) && ~isempty(loads), 'MCA:CoDesignEmptyFilter', 'No co-design cell selected.');

source_cfg = MCA_Official_Config(cfg.capacity_reference_mode);
capacity_path = fullfile(source_cfg.results_root, 'Capacity_Reference_Frozen.csv');
assert(exist(capacity_path, 'file') == 2, 'MCA:CapacityReferenceMissing', ...
    'Missing frozen capacity reference: %s', capacity_path);
capacity_tbl = readtable(capacity_path, 'TextType', 'string');
MCA_Write_Manifest(cfg, {mfilename('fullpath'), ...
    fullfile(fileparts(mfilename('fullpath')), 'MCA_Apply_Infrastructure_Profile.m'), ...
    fullfile(fileparts(mfilename('fullpath')), 'MCA_Prepare_CoDesign_Cell.m'), ...
    fullfile(fileparts(mfilename('fullpath')), 'Validate_MCA_Capacity_CoDesign.m')});

slot_rows = repmat(slot_template(), 0, 1);
suffix = phase_suffix(profiles, active_load_union(cfg, profiles, loads), run_indices);
checkpoint = fullfile(cfg.results_root, ['CapacityCoDesign_Checkpoint_' suffix '.mat']);
checkpoint_state = struct(); checkpoint_key = ""; checkpoint_slot = 0;
if exist(checkpoint, 'file')
    saved = load(checkpoint); slot_rows = saved.slot_rows;
    checkpoint_state = saved.checkpoint_state; checkpoint_key = saved.checkpoint_key;
    checkpoint_slot = saved.checkpoint_slot;
    fprintf('Resuming %s from %d saved slot rows.\n', suffix, numel(slot_rows));
end

for p = 1:numel(profiles)
    profile = profiles(p);
    profile_loads = loads;
    if isfield(cfg, 'codesign_profile_loads')
        profile_loads = intersect(loads, cfg.codesign_profile_loads.(char(profile)), 'stable');
    end
    assert(~isempty(profile_loads), 'MCA:CoDesignProfileLoads', 'No load selected for %s.', profile);
    ref = capacity_tbl(capacity_tbl.Profile == profile, :);
    assert(height(ref) == 1, 'MCA:CapacityReferenceProfile', 'Missing/duplicate capacity for %s.', profile);
    capacity_ref = ref.CapacityRef(1);
    profile_idx = find(string(cfg.infrastructure_profiles) == profile, 1);
    for local_load_idx = 1:numel(profile_loads)
        lambda = profile_loads(local_load_idx); N = max(1, round(capacity_ref * lambda));
        load_idx = find(abs(cfg.normalized_loads - lambda) < 1e-12, 1);
        for run = run_indices
            cell_key = sprintf('%s/L%.6f/R%d', profile, lambda, run);
            completed = completed_slot_count(slot_rows, profile, lambda, run, cfg.algorithms);
            if completed == cfg.replay_slots, continue; end
            if completed > 0
                assert(checkpoint_key == string(cell_key) && checkpoint_slot == completed, ...
                    'MCA:CoDesignResumeState', 'Checkpoint mismatch for %s.', cell_key);
                state = checkpoint_state;
            else
                state = initialize_state(cfg.algorithms);
            end
            for slot = (completed + 1):cfg.replay_slots
                env_seed = cfg.seed_base + 200000000 + 100000000 * profile_idx + ...
                    1000000 * load_idx + 1000 * run + slot;
                rng(env_seed, 'twister');
                [arr_task, base_fog, arr_thing, DNN_Data] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
                [base_fog, base_meta] = MCA_Apply_Infrastructure_Profile(base_fog, profile);
                for a = 1:numel(cfg.algorithms)
                    policy = cfg.algorithms{a}; pending = state.(policy);
                    prepared = MCA_Prepare_CoDesign_Cell(policy, pending, arr_task, arr_thing, ...
                        base_fog, DNN_Data, capacity_ref, lambda, N, cfg);
                    Task = prepared.Task; Thing = prepared.Thing; Fog = prepared.Fog;
                    % Generate the schedule under the frozen base profile. Capacity
                    % variants change only deployment resources, not the search path.
                    Pre = build_pre_struct_tier1(Task, base_fog, Thing, DNN_Data);
                    Pre.Mean_Deadline = mean(Task(:, 3)); Pre.Violation_Mode = cfg.violation_mode;
                    Pre.BacklogIn = size(pending.Task, 1); Pre.Arrivals = size(arr_task, 1);
                    Pre.ReplayScaleN = N; Pre.FullBacklogStreak = pending.FullBacklogStreak;
                    solver = policy;
                    if startsWith(upper(policy), 'ALMV9'), solver = 'ALMv9'; end
                    if startsWith(upper(policy), 'ALMV9'), solver_seed_offset = 4000; else, solver_seed_offset = 1000 * a; end
                    rng(env_seed + solver_seed_offset, 'twister');
                    t0 = tic; theta = MCA_Solve(solver, Task, base_fog, Thing, DNN_Data, Pre, cfg); runtime = toc(t0);
                    EvalPre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
                    EvalPre.Mean_Deadline = mean(Task(:, 3)); EvalPre.Violation_Mode = cfg.violation_mode;
                    EvalPre.BacklogIn = size(pending.Task, 1); EvalPre.Arrivals = size(arr_task, 1);
                    EvalPre.ReplayScaleN = N; EvalPre.FullBacklogStreak = pending.FullBacklogStreak;
                    m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, EvalPre, ...
                        sprintf('co-design/%s/L%.3f/R%d/S%d/%s', profile, lambda, run, slot, policy));
                    unresolved = m.SatisfiedVector < 0.5;
                    backlog_before_cap = sum(unresolved); cap = round(cfg.replay_backlog_cap_ratio * N);
                    keep_count = min(backlog_before_cap, cap);
                    if keep_count == 0, keep = zeros(0, 1); else, keep = find(unresolved, keep_count, 'first'); end
                    state.(policy).Task = Task(keep, :); state.(policy).Thing = Thing(keep, :);
                    if keep_count >= cap && cap > 0
                        state.(policy).FullBacklogStreak = Pre.FullBacklogStreak + 1;
                    else
                        state.(policy).FullBacklogStreak = 0;
                    end
                    slot_rows(end + 1) = make_slot(cfg, profile, lambda, capacity_ref, N, run, slot, ...
                        env_seed, policy, size(pending.Task, 1), size(arr_task, 1), numel(keep), ...
                        max(0, backlog_before_cap - cap), runtime, m, prepared, base_meta); %#ok<AGROW>
                end
                checkpoint_state = state; checkpoint_key = string(cell_key); checkpoint_slot = slot;
                save_checkpoint_atomic(checkpoint, slot_rows, cfg, profiles, loads, run_indices, ...
                    checkpoint_state, checkpoint_key, checkpoint_slot);
            end
        end
    end
end

slot_tbl = struct2table(slot_rows);
run_rows = repmat(run_template(), 0, 1);
for p = 1:numel(profiles)
    profile_loads = loads;
    if isfield(cfg, 'codesign_profile_loads')
        profile_loads = intersect(loads, cfg.codesign_profile_loads.(char(profiles(p))), 'stable');
    end
    for l = 1:numel(profile_loads)
        for run = run_indices
            for a = 1:numel(cfg.algorithms)
                mask = slot_tbl.Profile == profiles(p) & abs(slot_tbl.NormalizedLoadTarget - profile_loads(l)) < 1e-12 & ...
                    slot_tbl.Run == run & slot_tbl.Algorithm == string(cfg.algorithms{a});
                run_rows(end + 1) = make_run(cfg, slot_tbl(mask, :)); %#ok<AGROW>
            end
        end
    end
end
run_tbl = struct2table(run_rows);
writetable(slot_tbl, fullfile(cfg.results_root, ['CapacityCoDesign_SlotLevel_' suffix '.csv']));
writetable(run_tbl, fullfile(cfg.results_root, ['CapacityCoDesign_RunLevel_' suffix '.csv']));
save(fullfile(cfg.results_root, ['CapacityCoDesign_Results_' suffix '.mat']), 'slot_tbl', 'run_tbl', 'cfg');
Validate_MCA_Capacity_CoDesign(slot_tbl, run_tbl, cfg, false);
fprintf('CAPACITY CO-DESIGN %s PASS: %d slot rows, %d run rows.\n', ...
    upper(cfg.mode), height(slot_tbl), height(run_tbl));
end

function union_loads = active_load_union(cfg, profiles, requested_loads)
union_loads = [];
for p = 1:numel(profiles)
    profile_loads = requested_loads;
    if isfield(cfg, 'codesign_profile_loads')
        profile_loads = intersect(requested_loads, cfg.codesign_profile_loads.(char(profiles(p))), 'stable');
    end
    union_loads = union(union_loads, profile_loads, 'stable');
end
end

function save_checkpoint_atomic(checkpoint, slot_rows, cfg, profiles, loads, run_indices, ...
        checkpoint_state, checkpoint_key, checkpoint_slot)
tmp = [checkpoint '.tmp'];
save(tmp, 'slot_rows', 'cfg', 'profiles', 'loads', 'run_indices', ...
    'checkpoint_state', 'checkpoint_key', 'checkpoint_slot');
[ok, msg] = movefile(tmp, checkpoint, 'f');
assert(ok, 'MCA:CoDesignCheckpoint', 'Could not commit checkpoint: %s', msg);
end

function count = completed_slot_count(rows, profile, lambda, run, algorithms)
if isempty(rows), count = 0; return; end
names = string({rows.Algorithm}); profiles = string({rows.Profile}); loads = [rows.NormalizedLoadTarget];
counts = zeros(numel(algorithms), 1);
for a = 1:numel(algorithms)
    counts(a) = sum(profiles == profile & abs(loads - lambda) < 1e-12 & ...
        [rows.Run] == run & names == string(algorithms{a}));
end
assert(all(counts == counts(1)), 'MCA:CoDesignPartialPair', 'Policies have unequal slot counts.');
count = counts(1);
end

function state = initialize_state(algorithms)
state = struct();
for i = 1:numel(algorithms)
    state.(algorithms{i}) = struct('Task', zeros(0, 6), 'Thing', zeros(0, 6), 'FullBacklogStreak', 0);
end
end

function suffix = phase_suffix(profiles, loads, runs)
if numel(profiles) == 1, p = char(profiles(1)); else, p = sprintf('P%d', numel(profiles)); end
if numel(loads) == 1, l = sprintf('L%03d', round(loads(1) * 100)); else, l = sprintf('L%d', numel(loads)); end
suffix = sprintf('%s_%s_R%dto%d', p, l, runs(1), runs(end));
end

function row = slot_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'Profile', "", ...
    'NormalizedLoadTarget', 0, 'CapacityRef', 0, 'N', 0, 'Run', 0, 'Slot', 0, ...
    'EnvironmentSeed', 0, 'Algorithm', "", 'BacklogIn', 0, 'Arrivals', 0, ...
    'OfferedTasks', 0, 'SchedulerTasks', 0, 'AdmissionRejectCount', 0, ...
    'SatisfiedCount', 0, 'Sat', 0, 'Admission', 0, 'ResourceViolation', 0, ...
    'CompositeViolation', 0, 'BacklogOut', 0, 'DroppedByQueueCap', 0, ...
    'MemoryBlockCount', 0, 'IntrinsicLatencyBlockCount', 0, 'SpilloverBlockCount', 0, ...
    'FeasibleMissedCount', 0, 'DeadlineMissCount', 0, 'AdmissionActive', false, ...
    'CapacityActive', false, 'CapacityBoost', 1, 'ElasticComputeAdded', 0, ...
    'ElasticMemoryAddedMB', 0, 'ElasticBandwidthAddedMbps', 0, 'RuntimeSec', 0);
end

function row = make_slot(cfg, profile, lambda, capacity_ref, N, run, slot, seed, policy, ...
        backlog_in, arrivals, backlog_out, cap_drop, runtime, m, prepared, base_meta)
row = slot_template(); offered = backlog_in + arrivals;
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.Profile = profile; row.NormalizedLoadTarget = lambda; row.CapacityRef = capacity_ref;
row.N = N; row.Run = run; row.Slot = slot; row.EnvironmentSeed = seed; row.Algorithm = string(policy);
row.BacklogIn = backlog_in; row.Arrivals = arrivals; row.OfferedTasks = offered;
row.SchedulerTasks = m.TaskCount; row.AdmissionRejectCount = prepared.AdmissionRejectCount;
row.SatisfiedCount = m.SatisfiedCount; row.Sat = 100 * m.SatisfiedCount / max(1, offered);
row.Admission = 100 * m.AdmittedCount / max(1, offered);
row.ResourceViolation = 100 * m.ResourceViolationCount / max(1, offered);
row.CompositeViolation = 100 - row.Sat; row.BacklogOut = backlog_out;
row.DroppedByQueueCap = cap_drop; row.MemoryBlockCount = m.MemoryBlockCount;
row.IntrinsicLatencyBlockCount = m.IntrinsicLatencyBlockCount;
row.SpilloverBlockCount = m.SpilloverBlockCount; row.FeasibleMissedCount = m.FeasibleMissedCount;
row.DeadlineMissCount = m.DeadlineMissCount; row.AdmissionActive = prepared.AdmissionActive;
row.CapacityActive = prepared.CapacityActive; row.CapacityBoost = prepared.CapacityBoost;
row.ElasticComputeAdded = base_meta.TotalCompute * (prepared.CapacityBoost - 1);
row.ElasticMemoryAddedMB = base_meta.TotalMemoryMB * (prepared.CapacityBoost - 1);
row.ElasticBandwidthAddedMbps = base_meta.TotalBandwidthMbps * (prepared.CapacityBoost - 1);
row.RuntimeSec = runtime;
end

function row = run_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'Profile', "", ...
    'NormalizedLoadTarget', 0, 'CapacityRef', 0, 'N', 0, 'Run', 0, 'Algorithm', "", ...
    'Slots', 0, 'MeanSat', 0, 'TotalSatisfied', 0, 'AdmissionRejects', 0, ...
    'BacklogAUC', 0, 'QueueCapDrops', 0, 'CapacityActiveSlots', 0, ...
    'MeanCapacityBoost', 0, 'ElasticComputeSlotUnits', 0, 'MeanRuntimeSec', 0);
end

function row = make_run(cfg, block)
assert(height(block) > 0, 'MCA:CoDesignRunEmpty', 'Cannot summarize empty run.');
row = run_template(); row.SchemaVersion = string(cfg.schema_version);
row.EvidenceClass = upper(string(cfg.mode)); row.Profile = block.Profile(1);
row.NormalizedLoadTarget = block.NormalizedLoadTarget(1); row.CapacityRef = block.CapacityRef(1);
row.N = block.N(1); row.Run = block.Run(1); row.Algorithm = block.Algorithm(1);
row.Slots = height(block); row.MeanSat = mean(block.Sat); row.TotalSatisfied = sum(block.SatisfiedCount);
row.AdmissionRejects = sum(block.AdmissionRejectCount); row.BacklogAUC = sum(block.BacklogOut);
row.QueueCapDrops = sum(block.DroppedByQueueCap); row.CapacityActiveSlots = sum(block.CapacityActive);
row.MeanCapacityBoost = mean(block.CapacityBoost);
row.ElasticComputeSlotUnits = sum(block.ElasticComputeAdded); row.MeanRuntimeSec = mean(block.RuntimeSec);
end
