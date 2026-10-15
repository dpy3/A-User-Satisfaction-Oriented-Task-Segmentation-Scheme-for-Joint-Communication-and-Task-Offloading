function status_tbl = Check_MCA_Replay_Status(mode)
if nargin < 1 || isempty(mode), mode = 'selectorformal'; end
cfg = MCA_Official_Setup(mode);
if strcmpi(cfg.mode, 'replaytransitionpilot')
    specs = [210, 1, 5; 240, 1, 5; 270, 1, 5];
elseif ismember(lower(string(cfg.mode)), ["selectorv9calibration", "selectorv9calibrationaudit", "selectorv9calibrationauditfast", "selectorv9calibrationaudit2", "selectorv9formal"])
    if ismember(lower(string(cfg.mode)), ["selectorv9calibrationaudit", "selectorv9calibrationauditfast", "selectorv9calibrationaudit2"])
        specs = [240, 6, 7; 240, 8, 10; 270, 6, 7; 270, 8, 10; 300, 6, 7; 300, 8, 10];
    elseif strcmpi(cfg.mode, 'selectorv9formal')
        specs = [240, 11, 20; 240, 21, 30; 270, 11, 20; 270, 21, 30; 300, 11, 20; 300, 21, 30];
    else
        rr = cfg.required_replay_runs;
        specs = [cfg.replay_scales(:), repmat(rr(1), numel(cfg.replay_scales), 1), ...
            repmat(rr(end), numel(cfg.replay_scales), 1)];
    end
else
    specs = [180, 1, 2; 180, 3, 11; 180, 12, 20; 300, 1, 10; 300, 11, 20];
end
rows = repmat(struct('Scale', 0, 'FirstRun', 0, 'LastRun', 0, ...
    'CompletedSlotRows', 0, 'TargetSlotRows', 0, 'Percent', 0, ...
    'FinalCSVExists', false, 'CheckpointTime', NaT), 0, 1);
for i = 1:size(specs, 1)
    N = specs(i, 1); first_run = specs(i, 2); last_run = specs(i, 3);
    suffix = sprintf('N%d_R%dto%d', N, first_run, last_run);
    checkpoint = fullfile(cfg.results_root, ['Replay_Checkpoint_' suffix '.mat']);
    completed = 0; checkpoint_time = NaT;
    if exist(checkpoint, 'file')
        info = dir(checkpoint); checkpoint_time = datetime(info.datenum, 'ConvertFrom', 'datenum');
        try
            saved = load(checkpoint, 'slot_rows');
            completed = numel(saved.slot_rows);
        catch err
            warning('MCA:CheckpointBusy', 'Could not read %s: %s', checkpoint, err.message);
        end
    end
    target = (last_run - first_run + 1) * cfg.replay_slots * numel(cfg.algorithms);
    rows(end + 1) = struct('Scale', N, 'FirstRun', first_run, 'LastRun', last_run, ...
        'CompletedSlotRows', completed, 'TargetSlotRows', target, ...
        'Percent', 100 * completed / target, ...
        'FinalCSVExists', exist(fullfile(cfg.results_root, ['Replay_SlotLevel_' suffix '.csv']), 'file') == 2, ...
        'CheckpointTime', checkpoint_time); %#ok<AGROW>
end
status_tbl = struct2table(rows);
disp(status_tbl);
fprintf('Overall replay completion: %.2f%%\n', ...
    100 * sum(status_tbl.CompletedSlotRows) / sum(status_tbl.TargetSlotRows));
end
