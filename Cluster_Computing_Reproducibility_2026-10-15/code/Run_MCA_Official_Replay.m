function Run_MCA_Official_Replay(mode, run_indices, scale_filter)
% Stateful replay: unresolved task and user rows persist into the next slot.
if nargin < 1, mode = 'smoke'; end
cfg = MCA_Official_Setup(mode);
if nargin < 2 || isempty(run_indices), run_indices = 1:cfg.replay_runs; end
scales = cfg.replay_scales;
if nargin >= 3 && ~isempty(scale_filter), scales = intersect(scales, scale_filter, 'stable'); end
assert(~isempty(scales), 'MCA:EmptyReplayScales', 'No replay scale selected.');
MCA_Write_Manifest(cfg, {mfilename('fullpath')});
slot_rows = repmat(slot_template(), 0, 1);
suffix = replay_suffix(scales, run_indices);
checkpoint = fullfile(cfg.results_root, ['Replay_Checkpoint_' suffix '.mat']);
checkpoint_state = struct(); checkpoint_N = 0; checkpoint_run = 0; checkpoint_slot = 0;
if exist(checkpoint, 'file')
    saved = load(checkpoint);
    slot_rows = saved.slot_rows;
    if isfield(saved, 'checkpoint_state'), checkpoint_state = saved.checkpoint_state; end
    if isfield(saved, 'checkpoint_N'), checkpoint_N = saved.checkpoint_N; end
    if isfield(saved, 'checkpoint_run'), checkpoint_run = saved.checkpoint_run; end
    if isfield(saved, 'checkpoint_slot'), checkpoint_slot = saved.checkpoint_slot; end
    fprintf('Resuming %s from %d saved slot rows.\n', suffix, numel(slot_rows));
end

fprintf('MCA replay %s: scales=%s runs=%s slots=%d\n', ...
    upper(cfg.mode), mat2str(scales), mat2str(run_indices), cfg.replay_slots);
for scale_pos = 1:numel(scales)
    N = scales(scale_pos);
    replay_seed_scales = cfg.replay_scales;
    if isfield(cfg, 'replay_seed_scale_reference')
        replay_seed_scales = cfg.replay_seed_scale_reference;
    end
    seed_scale_idx = find(replay_seed_scales == N, 1);
    assert(~isempty(seed_scale_idx), 'MCA:ReplaySeedScale', 'N=%d lacks replay seed reference.', N);
    fog_num = resolve_fog_num(N, cfg);
    for run = run_indices
        completed_slots = completed_slot_count(slot_rows, N, run, cfg.algorithms);
        if completed_slots == cfg.replay_slots
            fprintf('Skipping complete N=%d run=%d.\n', N, run);
            continue;
        elseif completed_slots > 0
            assert(checkpoint_N == N && checkpoint_run == run && checkpoint_slot == completed_slots, ...
                'MCA:ReplayResumeState', 'Checkpoint state does not match partial N=%d run=%d.', N, run);
            assert(~isempty(fieldnames(checkpoint_state)), 'MCA:ReplayResumeState', 'Missing backlog state.');
            state = checkpoint_state;
        else
            state = initialize_state(cfg.algorithms);
        end
        for slot = (completed_slots + 1):cfg.replay_slots
            env_seed = cfg.seed_base + 10000000 * seed_scale_idx + 10000 * run + slot;
            rng(env_seed, 'twister');
            [arr_task, Fog, arr_thing, DNN_Data] = generate_tier1_env_trace(N, fog_num);
            theta_cache = struct();
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
                if isfield(pending, 'FullBacklogStreak')
                    Pre.FullBacklogStreak = pending.FullBacklogStreak;
                else
                    Pre.FullBacklogStreak = 0;
                end
                rng(env_seed + 1000 * a, 'twister');
                t0 = tic;
                if strcmpi(alg, 'ALMv9') && isfield(cfg, 'reuse_alm_for_v9') && ...
                        cfg.reuse_alm_for_v9 && isfield(theta_cache, 'ALM')
                    theta = MCA_Apply_Overload_Selector(theta_cache.ALM, Task, Fog, DNN_Data, Pre, cfg);
                else
                    theta = MCA_Solve(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
                end
                runtime = toc(t0);
                theta_cache.(alg) = theta;
                m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
                    sprintf('replay/N%d/R%d/S%d/%s', N, run, slot, alg));
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
                dropped_by_cap = max(0, backlog_before_cap - cap);
                slot_rows(end + 1) = make_slot(cfg, N, run, slot, env_seed, alg, ...
                    size(pending.Task, 1), size(arr_task, 1), numel(keep), dropped_by_cap, runtime, m); %#ok<AGROW>
            end
            checkpoint_state = state; checkpoint_N = N; checkpoint_run = run; checkpoint_slot = slot;
            save_checkpoint_atomic(checkpoint, slot_rows, cfg, scales, run_indices, ...
                checkpoint_state, checkpoint_N, checkpoint_run, checkpoint_slot);
        end
    end
end

slot_tbl = struct2table(slot_rows);
run_rows = repmat(run_template(), 0, 1);
for N = scales(:)'
    for run = run_indices(:)'
        for a = 1:numel(cfg.algorithms)
            alg = cfg.algorithms{a};
            all_alg = string({slot_rows.Algorithm});
            mask = [slot_rows.N] == N & [slot_rows.Run] == run & all_alg == string(alg);
            run_rows(end + 1) = make_run(cfg, N, run, alg, slot_rows(mask)); %#ok<AGROW>
        end
    end
end
run_tbl = struct2table(run_rows);
writetable(slot_tbl, fullfile(cfg.results_root, ['Replay_SlotLevel_' suffix '.csv']));
writetable(run_tbl, fullfile(cfg.results_root, ['Replay_RunLevel_' suffix '.csv']));
save(fullfile(cfg.results_root, ['Replay_Results_' suffix '.mat']), 'slot_tbl', 'run_tbl', 'cfg');
Validate_MCA_Official_Replay(slot_tbl, run_tbl, cfg, false);
fprintf('REPLAY %s PASS: %d slot rows, %d run rows.\n', upper(cfg.mode), height(slot_tbl), height(run_tbl));
end

function save_checkpoint_atomic(checkpoint, slot_rows, cfg, scales, run_indices, ...
        checkpoint_state, checkpoint_N, checkpoint_run, checkpoint_slot)
% Keep the previous checkpoint intact if MATLAB or the host is interrupted mid-save.
tmp = [checkpoint '.tmp'];
save(tmp, 'slot_rows', 'cfg', 'scales', 'run_indices', ...
    'checkpoint_state', 'checkpoint_N', 'checkpoint_run', 'checkpoint_slot');
ok = false; msg = '';
for attempt = 1:20
    [ok, msg] = movefile(tmp, checkpoint, 'f');
    if ok, break; end
    pause(0.1 * attempt);
end
if ~ok
    warning('MCA:CheckpointCommit', ...
        'Could not commit checkpoint %s after retries; continuing with the previous checkpoint: %s', ...
        checkpoint, msg);
    if exist(tmp, 'file'), delete(tmp); end
end
end

function suffix = replay_suffix(scales, run_indices)
scale_text = strjoin(string(scales(:)'), '-');
suffix = sprintf('N%s_R%dto%d', scale_text, run_indices(1), run_indices(end));
end

function count = completed_slot_count(rows, N, run, algorithms)
if isempty(rows), count = 0; return; end
names = string({rows.Algorithm});
counts = zeros(numel(algorithms), 1);
for a = 1:numel(algorithms)
    counts(a) = sum([rows.N] == N & [rows.Run] == run & names == string(algorithms{a}));
end
assert(all(counts == counts(1)), 'MCA:ReplayPartialPair', ...
    'Algorithms have unequal completed slot counts at N=%d run=%d.', N, run);
count = counts(1);
end

function state = initialize_state(algorithms)
state = struct();
for i = 1:numel(algorithms)
    state.(algorithms{i}) = struct('Task', zeros(0, 6), 'Thing', zeros(0, 6), ...
        'FullBacklogStreak', 0);
end
end

function row = slot_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, 'Run', 0, 'Slot', 0, ...
    'EnvironmentSeed', 0, 'Algorithm', "", 'BacklogIn', 0, 'Arrivals', 0, ...
    'OfferedTasks', 0, 'SatisfiedCount', 0, 'Sat', 0, 'Admission', 0, ...
    'ResourceViolation', 0, 'CompositeViolation', 0, 'BacklogOut', 0, ...
    'BacklogRatioIn', 0, 'FullBacklogStreakIn', 0, 'OverloadModeActive', false, ...
    'DroppedByQueueCap', 0, 'DeadlineMissCount', 0, 'MemoryBlockCount', 0, ...
    'IntrinsicLatencyBlockCount', 0, 'SpilloverBlockCount', 0, ...
    'FeasibleMissedCount', 0, 'RuntimeSec', 0);
end

function row = make_slot(cfg, N, run, slot, seed, alg, backlog_in, arrivals, backlog_out, cap_drop, runtime, m)
row = slot_template();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.N = N; row.Run = run; row.Slot = slot; row.EnvironmentSeed = seed; row.Algorithm = string(alg);
row.BacklogIn = backlog_in; row.Arrivals = arrivals; row.OfferedTasks = m.TaskCount;
row.SatisfiedCount = m.SatisfiedCount; row.Sat = m.Sat; row.Admission = m.Admission;
row.ResourceViolation = m.ResourceViolation; row.CompositeViolation = m.CompositeViolation;
row.BacklogOut = backlog_out; row.DroppedByQueueCap = cap_drop;
row.BacklogRatioIn = backlog_in / max(1, N);
if isfield(m, 'FullBacklogStreakIn'), row.FullBacklogStreakIn = m.FullBacklogStreakIn; end
if isfield(m, 'OverloadModeActive'), row.OverloadModeActive = logical(m.OverloadModeActive); end
row.DeadlineMissCount = m.DeadlineMissCount; row.MemoryBlockCount = m.MemoryBlockCount;
row.IntrinsicLatencyBlockCount = m.IntrinsicLatencyBlockCount;
row.SpilloverBlockCount = m.SpilloverBlockCount; row.FeasibleMissedCount = m.FeasibleMissedCount;
row.RuntimeSec = runtime;
end

function row = run_template()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, 'Run', 0, ...
    'Algorithm', "", 'Slots', 0, 'MeanSat', 0, 'TotalSatisfied', 0, ...
    'BacklogAUC', 0, 'PeakBacklog', 0, 'FinalBacklog', 0, ...
    'QueueCapDrops', 0, 'DeadlineMisses', 0, 'MemoryBlocks', 0, ...
    'IntrinsicLatencyBlocks', 0, 'SpilloverBlocks', 0, 'FeasibleMisses', 0, ...
    'MeanRuntimeSec', 0);
end

function row = make_run(cfg, N, run, alg, block)
row = run_template();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.N = N; row.Run = run; row.Algorithm = string(alg); row.Slots = numel(block);
row.MeanSat = mean([block.Sat]); row.TotalSatisfied = sum([block.SatisfiedCount]);
row.BacklogAUC = sum([block.BacklogOut]); row.PeakBacklog = max([block.BacklogOut]);
row.FinalBacklog = block(end).BacklogOut; row.QueueCapDrops = sum([block.DroppedByQueueCap]);
row.DeadlineMisses = sum([block.DeadlineMissCount]);
row.MemoryBlocks = sum([block.MemoryBlockCount]);
row.IntrinsicLatencyBlocks = sum([block.IntrinsicLatencyBlockCount]);
row.SpilloverBlocks = sum([block.SpilloverBlockCount]);
row.FeasibleMisses = sum([block.FeasibleMissedCount]);
row.MeanRuntimeSec = mean([block.RuntimeSec]);
end

function fog_num = resolve_fog_num(N, cfg)
if strcmpi(cfg.fog_mode, 'fixed')
    fog_num = cfg.fog_num_fixed;
else
    fog_num = max(cfg.min_fog_nodes, round(N / cfg.fog_divisor));
end
end
