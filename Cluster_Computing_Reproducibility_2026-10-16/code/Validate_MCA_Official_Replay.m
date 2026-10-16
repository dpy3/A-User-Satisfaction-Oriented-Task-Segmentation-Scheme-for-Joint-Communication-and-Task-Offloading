function Validate_MCA_Official_Replay(slot_tbl, run_tbl, cfg, require_complete)
if nargin < 4, require_complete = false; end
assert(height(slot_tbl) > 0 && height(run_tbl) > 0, 'MCA:ReplayEmpty', 'Replay tables are empty.');
assert(all(slot_tbl.ResourceViolation == 0), 'MCA:ReplayResourceViolation', 'Replay contains resource violations.');
assert(all(abs(slot_tbl.CompositeViolation - (100 - slot_tbl.Sat)) < 1e-8), ...
    'MCA:ReplayCompositeIdentity', 'Replay composite identity failed.');
assert(all(slot_tbl.OfferedTasks == slot_tbl.BacklogIn + slot_tbl.Arrivals), ...
    'MCA:ReplayFlowIdentity', 'Replay offered-task flow identity failed.');
diagnostic_fields = {'DeadlineMissCount','MemoryBlockCount','IntrinsicLatencyBlockCount', ...
    'SpilloverBlockCount','FeasibleMissedCount'};
if all(ismember(diagnostic_fields, slot_tbl.Properties.VariableNames))
    diagnostic_values = slot_tbl{:, diagnostic_fields};
    assert(all(diagnostic_values(:) >= 0 & diagnostic_values(:) == floor(diagnostic_values(:))), ...
        'MCA:ReplayDiagnosticCount', 'Replay diagnostic counts must be nonnegative integers.');
    classified = slot_tbl.MemoryBlockCount + slot_tbl.IntrinsicLatencyBlockCount + ...
        slot_tbl.SpilloverBlockCount + slot_tbl.FeasibleMissedCount;
    assert(all(classified == slot_tbl.OfferedTasks - slot_tbl.SatisfiedCount), ...
        'MCA:ReplayFailurePartition', 'Bottleneck causes do not partition unsatisfied tasks.');
    assert(all(slot_tbl.DeadlineMissCount <= slot_tbl.OfferedTasks - slot_tbl.SatisfiedCount), ...
        'MCA:ReplayDeadlineCount', 'Deadline misses exceed unsatisfied tasks.');
end
assert(all(run_tbl.Slots == cfg.replay_slots), 'MCA:ReplaySlotCount', 'Run summary has wrong slot count.');

slot_keys = strcat(string(slot_tbl.N), "/", string(slot_tbl.Run), "/", ...
    string(slot_tbl.Slot), "/", slot_tbl.Algorithm);
run_keys = strcat(string(run_tbl.N), "/", string(run_tbl.Run), "/", run_tbl.Algorithm);
assert(numel(unique(slot_keys)) == height(slot_tbl), 'MCA:ReplayDuplicateKey', 'Replay contains duplicate slot keys.');
assert(numel(unique(run_keys)) == height(run_tbl), 'MCA:ReplayDuplicateRun', 'Replay contains duplicate run keys.');

[groups, ~] = findgroups(slot_tbl.N, slot_tbl.Run, slot_tbl.Slot);
counts = splitapply(@numel, slot_tbl.Algorithm, groups);
assert(all(counts == numel(cfg.algorithms)), 'MCA:ReplayAlgorithmCount', 'A slot lacks algorithms.');
for g = unique(groups)'
    assert(isequal(sort(slot_tbl.Algorithm(groups == g)), sort(string(cfg.algorithms(:)))), ...
        'MCA:ReplayAlgorithmSet', 'Algorithm set differs within a replay slot.');
    assert(numel(unique(slot_tbl.EnvironmentSeed(groups == g))) == 1, ...
        'MCA:ReplayEnvironmentPairing', 'Algorithms do not share an environment seed.');
end

for i = 1:height(run_tbl)
    mask = slot_tbl.N == run_tbl.N(i) & slot_tbl.Run == run_tbl.Run(i) & ...
        slot_tbl.Algorithm == run_tbl.Algorithm(i);
    assert(sum(mask) == cfg.replay_slots, 'MCA:ReplayRunLink', 'Run summary lacks slot rows.');
end

if require_complete
    expected_runs = numel(cfg.replay_scales) * cfg.replay_runs;
    required_runs = 1:cfg.replay_runs;
    if isfield(cfg, 'required_replay_runs') && ~isempty(cfg.required_replay_runs)
        required_runs = cfg.required_replay_runs;
        expected_runs = numel(cfg.replay_scales) * numel(required_runs);
    end
    expected_slot_rows = expected_runs * cfg.replay_slots * numel(cfg.algorithms);
    expected_run_rows = expected_runs * numel(cfg.algorithms);
    assert(height(slot_tbl) == expected_slot_rows, 'MCA:ReplayIncomplete', ...
        'Expected %d slot rows, found %d.', expected_slot_rows, height(slot_tbl));
    assert(height(run_tbl) == expected_run_rows, 'MCA:ReplayIncomplete', ...
        'Expected %d run rows, found %d.', expected_run_rows, height(run_tbl));
    for N = cfg.replay_scales(:)'
        actual = sort(unique(run_tbl.Run(run_tbl.N == N)))';
        assert(isequal(actual, required_runs), 'MCA:ReplayRunCoverage', ...
            'N=%d does not contain required runs.', N);
    end
end
fprintf('REPLAY VALIDATION PASS: %d slot rows, %d run rows, complete=%d.\n', ...
    height(slot_tbl), height(run_tbl), require_complete);
end
