function output_path = Merge_MCA_Repair_Transfer(mode, require_complete)
if nargin < 1 || isempty(mode), mode = 'repairtransferformal'; end
if nargin < 2, require_complete = true; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'repairtransfer'), 'MCA:WrongMode', ...
    'Repair-transfer merger requires a repair-transfer mode.');

pattern = fullfile(cfg.results_root, 'RepairTransfer_RunLevel_S*_R*.csv');
files = dir(pattern);
canonical = fullfile(cfg.results_root, 'RepairTransfer_RunLevel.csv');
assert(~isempty(files) || exist(canonical, 'file') == 2, ...
    'MCA:NoRepairTransferShards', 'No repair-transfer shards were found.');

parts = cell(0, 1);
if exist(canonical, 'file') == 2
    parts{end + 1} = readtable(canonical, 'TextType', 'string'); %#ok<AGROW>
end
for i = 1:numel(files)
    parts{end + 1} = readtable(fullfile(files(i).folder, files(i).name), ...
        'TextType', 'string'); %#ok<AGROW>
end
tbl = vertcat(parts{:});
tbl = sortrows(tbl, {'N','Run','Algorithm'});
[~, unique_idx] = unique(tbl(:, {'N','Run','Seed','Algorithm'}), 'rows', 'stable');
tbl = tbl(sort(unique_idx), :);

expected = numel(cfg.static_scales) * numel(cfg.required_static_runs) * numel(cfg.algorithms);
if require_complete
    assert(height(tbl) == expected, 'MCA:IncompleteRepairTransferMerge', ...
        'Expected %d rows after merge, found %d.', expected, height(tbl));
    assert(isequal(sort(unique(tbl.N))', sort(cfg.static_scales)), ...
        'MCA:RepairTransferScaleSet', 'Merged scale set is incomplete.');
    assert(isequal(sort(unique(tbl.Run))', sort(cfg.required_static_runs)), ...
        'MCA:RepairTransferRunSet', 'Merged run set is incomplete.');
end

writetable(tbl, canonical);
Validate_MCA_Official_Results(canonical, cfg);
output_path = canonical;
fprintf('REPAIR TRANSFER MERGE PASS: %s (%d/%d rows)\n', ...
    canonical, height(tbl), expected);
end
