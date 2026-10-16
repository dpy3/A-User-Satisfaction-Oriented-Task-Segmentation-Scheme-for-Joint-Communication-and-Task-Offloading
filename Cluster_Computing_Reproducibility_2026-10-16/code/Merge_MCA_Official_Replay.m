function Merge_MCA_Official_Replay(mode, require_complete)
if nargin < 1 || isempty(mode), mode = 'selectorformal'; end
if nargin < 2, require_complete = false; end
cfg = MCA_Official_Setup(mode);
slot_files = dir(fullfile(cfg.results_root, 'Replay_SlotLevel_N*_R*to*.csv'));
run_files = dir(fullfile(cfg.results_root, 'Replay_RunLevel_N*_R*to*.csv'));
assert(~isempty(slot_files) && numel(slot_files) == numel(run_files), ...
    'MCA:ReplayShardFiles', 'Slot/run shard file counts differ or are empty.');

slot_tbl = table(); run_tbl = table();
index_rows = repmat(struct('SlotFile', "", 'RunFile', "", 'SlotRows', 0, 'RunRows', 0), 0, 1);
for i = 1:numel(slot_files)
    slot_path = fullfile(slot_files(i).folder, slot_files(i).name);
    expected_run_name = strrep(slot_files(i).name, 'Replay_SlotLevel_', 'Replay_RunLevel_');
    run_path = fullfile(slot_files(i).folder, expected_run_name);
    assert(exist(run_path, 'file') == 2, 'MCA:ReplayShardPair', 'Missing %s.', expected_run_name);
    s = readtable(slot_path, 'TextType', 'string');
    r = readtable(run_path, 'TextType', 'string');
    slot_tbl = [slot_tbl; s]; %#ok<AGROW>
    run_tbl = [run_tbl; r]; %#ok<AGROW>
    index_rows(end + 1) = struct('SlotFile', string(slot_files(i).name), ...
        'RunFile', string(expected_run_name), 'SlotRows', height(s), 'RunRows', height(r)); %#ok<AGROW>
end
slot_tbl = sortrows(slot_tbl, {'N','Run','Slot','Algorithm'});
run_tbl = sortrows(run_tbl, {'N','Run','Algorithm'});
Validate_MCA_Official_Replay(slot_tbl, run_tbl, cfg, require_complete);
writetable(slot_tbl, fullfile(cfg.results_root, 'Replay_SlotLevel_Merged.csv'));
writetable(run_tbl, fullfile(cfg.results_root, 'Replay_RunLevel_Merged.csv'));
writetable(struct2table(index_rows), fullfile(cfg.results_root, 'Replay_Shard_Index.csv'));
save(fullfile(cfg.results_root, 'Replay_Merged.mat'), 'slot_tbl', 'run_tbl', 'cfg', 'require_complete');
fprintf('MERGE PASS: %d shards, complete=%d.\n', numel(slot_files), require_complete);
end
