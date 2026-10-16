function out = MCA_Prepare_CoDesign_Cell(policy, pending, arr_task, arr_thing, ...
        Fog, DNN_Data, capacity_ref, lambda, N, cfg)
% Apply explicit admission and/or elastic-capacity actions before scheduling.
name = upper(char(string(policy)));
use_admission = ismember(name, {'ALMV9ADMISSION', 'ALMV9CODESIGN'});
use_capacity = ismember(name, {'ALMV9CAPACITY', 'ALMV9CODESIGN'});
backlog_ratio = size(pending.Task, 1) / max(1, N);
active = lambda >= cfg.codesign_load_trigger || ...
    backlog_ratio >= cfg.overload_backlog_ratio_threshold || ...
    pending.FullBacklogStreak >= cfg.overload_full_streak_threshold;

boost = 1.0;
if use_capacity && active
    boost = cfg.codesign_capacity_boost;
    Fog(:, 4) = Fog(:, 4) * boost;
    Fog(:, 7) = Fog(:, 7) * boost;
    Fog(:, 6) = Fog(:, 6) * boost;
    Fog(:, 8) = Fog(:, 8) * boost;
end

selected = (1:size(arr_task, 1))';
if use_admission && active
    % Keep the admission branch identical in the 2x2 design; capacity is
    % varied only at deployment and must not silently relax the intake cap.
    max_new = max(0, floor(cfg.codesign_admission_target_load * capacity_ref) - size(pending.Task, 1));
    max_new = min(max_new, size(arr_task, 1));
    if max_new < size(arr_task, 1)
        selected = rank_arrivals(arr_task, Fog, arr_thing, DNN_Data);
        selected = selected(1:max_new);
        selected = sort(selected);
    end
end

kept_task = arr_task(selected, :);
kept_thing = arr_thing(selected, :);
Task = [pending.Task; kept_task];
Thing = [pending.Thing; kept_thing];
Task(:, 1) = (1:size(Task, 1))';
out = struct('Task', Task, 'Thing', Thing, 'Fog', Fog, ...
    'AdmissionRejectCount', size(arr_task, 1) - numel(selected), ...
    'CapacityActive', use_capacity && active, 'AdmissionActive', use_admission && active, ...
    'CapacityBoost', boost, 'SystemModeActive', active);
end

function order = rank_arrivals(Task, Fog, Thing, DNN_Data)
Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
intrinsic = Pre.Comm + Pre.Comp;
best_intrinsic = min(intrinsic, [], 2);
feasible = any(intrinsic <= Task(:, 3), 2);
slack = Task(:, 3) - best_intrinsic;
[~, order] = sortrows([~feasible, best_intrinsic, -slack, Task(:, 1)], [1, 2, 3, 4]);
end
