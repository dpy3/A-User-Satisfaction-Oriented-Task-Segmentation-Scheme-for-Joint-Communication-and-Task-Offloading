function Merge_MCA_Capacity_Phase(mode, require_complete)
if nargin < 1 || isempty(mode), mode = 'capacityphasesmoke'; end
if nargin < 2, require_complete = true; end
cfg = MCA_Official_Setup(mode);
slot_files = dir(fullfile(cfg.results_root, 'CapacityPhase_SlotLevel_*.csv'));
run_files = dir(fullfile(cfg.results_root, 'CapacityPhase_RunLevel_*.csv'));
assert(~isempty(slot_files) && ~isempty(run_files), 'MCA:CapacityPhaseNoShards', ...
    'No capacity-phase shard CSVs found.');

slot_tbl = table();
for i = 1:numel(slot_files)
    block = readtable(fullfile(slot_files(i).folder, slot_files(i).name), 'TextType', 'string');
    slot_tbl = [slot_tbl; block]; %#ok<AGROW>
end
run_tbl = table();
for i = 1:numel(run_files)
    block = readtable(fullfile(run_files(i).folder, run_files(i).name), 'TextType', 'string');
    run_tbl = [run_tbl; block]; %#ok<AGROW>
end

profiles = string(cfg.infrastructure_profiles);
slot_tbl = slot_tbl(ismember(slot_tbl.Profile, profiles) & ...
    ismember(slot_tbl.NormalizedLoadTarget, cfg.normalized_loads) & ...
    ismember(slot_tbl.Run, cfg.required_replay_runs), :);
run_tbl = run_tbl(ismember(run_tbl.Profile, profiles) & ...
    ismember(run_tbl.NormalizedLoadTarget, cfg.normalized_loads) & ...
    ismember(run_tbl.Run, cfg.required_replay_runs), :);
slot_keys = strcat(slot_tbl.Profile, "/", string(slot_tbl.NormalizedLoadTarget), "/", ...
    string(slot_tbl.Run), "/", string(slot_tbl.Slot), "/", slot_tbl.Algorithm);
run_keys = strcat(run_tbl.Profile, "/", string(run_tbl.NormalizedLoadTarget), "/", ...
    string(run_tbl.Run), "/", run_tbl.Algorithm);
[~, keep_slot] = unique(slot_keys, 'stable');
[~, keep_run] = unique(run_keys, 'stable');
slot_tbl = slot_tbl(sort(keep_slot), :);
run_tbl = run_tbl(sort(keep_run), :);
slot_tbl = sortrows(slot_tbl, {'Profile','NormalizedLoadTarget','Run','Slot','Algorithm'});
run_tbl = sortrows(run_tbl, {'Profile','NormalizedLoadTarget','Run','Algorithm'});

Validate_MCA_Capacity_Phase(slot_tbl, run_tbl, cfg, require_complete);
writetable(slot_tbl, fullfile(cfg.results_root, 'CapacityPhase_SlotLevel_Merged.csv'));
writetable(run_tbl, fullfile(cfg.results_root, 'CapacityPhase_RunLevel_Merged.csv'));
save(fullfile(cfg.results_root, 'CapacityPhase_Merged.mat'), 'slot_tbl', 'run_tbl', 'cfg');
fprintf('CAPACITY PHASE MERGE %s PASS: %d slot rows, %d run rows.\n', ...
    upper(cfg.mode), height(slot_tbl), height(run_tbl));
end
