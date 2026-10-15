function Merge_MCA_Capacity_CoDesign(mode, require_complete)
if nargin < 1 || isempty(mode), mode = 'capacitycodesignsmoke'; end
if nargin < 2, require_complete = true; end
cfg = MCA_Official_Setup(mode);
slot_files = dir(fullfile(cfg.results_root, 'CapacityCoDesign_SlotLevel_*.csv'));
run_files = dir(fullfile(cfg.results_root, 'CapacityCoDesign_RunLevel_*.csv'));
assert(~isempty(slot_files) && ~isempty(run_files), 'MCA:CoDesignNoShards', 'No co-design shards found.');
slot_tbl = table(); run_tbl = table();
for i = 1:numel(slot_files)
    slot_tbl = [slot_tbl; readtable(fullfile(slot_files(i).folder, slot_files(i).name), 'TextType', 'string')]; %#ok<AGROW>
end
for i = 1:numel(run_files)
    run_tbl = [run_tbl; readtable(fullfile(run_files(i).folder, run_files(i).name), 'TextType', 'string')]; %#ok<AGROW>
end
profiles = string(cfg.infrastructure_profiles);
slot_tbl = slot_tbl(valid_cell_mask(slot_tbl, cfg, profiles) & ...
    ismember(slot_tbl.Run, cfg.required_replay_runs), :);
run_tbl = run_tbl(valid_cell_mask(run_tbl, cfg, profiles) & ...
    ismember(run_tbl.Run, cfg.required_replay_runs), :);
slot_keys = strcat(slot_tbl.Profile, "/", string(slot_tbl.NormalizedLoadTarget), "/", ...
    string(slot_tbl.Run), "/", string(slot_tbl.Slot), "/", slot_tbl.Algorithm);
run_keys = strcat(run_tbl.Profile, "/", string(run_tbl.NormalizedLoadTarget), "/", ...
    string(run_tbl.Run), "/", run_tbl.Algorithm);
[~, keep] = unique(slot_keys, 'stable'); slot_tbl = slot_tbl(sort(keep), :);
[~, keep] = unique(run_keys, 'stable'); run_tbl = run_tbl(sort(keep), :);
slot_tbl = sortrows(slot_tbl, {'Profile','NormalizedLoadTarget','Run','Slot','Algorithm'});
run_tbl = sortrows(run_tbl, {'Profile','NormalizedLoadTarget','Run','Algorithm'});
Validate_MCA_Capacity_CoDesign(slot_tbl, run_tbl, cfg, require_complete);
writetable(slot_tbl, fullfile(cfg.results_root, 'CapacityCoDesign_SlotLevel_Merged.csv'));
writetable(run_tbl, fullfile(cfg.results_root, 'CapacityCoDesign_RunLevel_Merged.csv'));
save(fullfile(cfg.results_root, 'CapacityCoDesign_Merged.mat'), 'slot_tbl', 'run_tbl', 'cfg');
fprintf('CAPACITY CO-DESIGN MERGE %s PASS: %d slot rows, %d run rows.\n', ...
    upper(cfg.mode), height(slot_tbl), height(run_tbl));
end

function mask = valid_cell_mask(tbl, cfg, profiles)
mask = false(height(tbl), 1);
for p = 1:numel(profiles)
    loads = cfg.normalized_loads;
    if isfield(cfg, 'codesign_profile_loads')
        loads = cfg.codesign_profile_loads.(char(profiles(p)));
    end
    mask = mask | (tbl.Profile == profiles(p) & ismember(tbl.NormalizedLoadTarget, loads));
end
end
