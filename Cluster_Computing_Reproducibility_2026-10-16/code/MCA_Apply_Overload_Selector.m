function theta_best = MCA_Apply_Overload_Selector(theta_alm, Task, Fog, DNN_Data, Pre, cfg)
% External selector-v9 wrapper used by replay to reuse the already computed
% ALM candidate in the same slot.
theta_base = repair_and_polish(theta_alm, Task, Fog, DNN_Data, Pre, cfg);
if ~overload_selector_active(Pre, cfg)
    theta_best = theta_base;
    return;
end

theta_throughput = build_overload_throughput_candidate(Task, Fog, DNN_Data, Pre);
theta_throughput = repair_and_polish(theta_throughput, Task, Fog, DNN_Data, Pre, cfg);

base_score = overload_candidate_score(theta_base, theta_base, Task, Fog, DNN_Data, Pre, cfg);
throughput_score = overload_candidate_score(theta_throughput, theta_base, Task, Fog, DNN_Data, Pre, cfg);
if lexicographic_better(throughput_score, base_score)
    theta_best = theta_throughput;
else
    theta_best = theta_base;
end
end

function active = overload_selector_active(Pre, cfg)
active = false;
if ~isfield(cfg, 'enable_overload_selector') || ~cfg.enable_overload_selector
    return;
end
if ~isfield(Pre, 'ReplayScaleN') || Pre.ReplayScaleN <= 0
    return;
end
backlog_ratio = 0;
if isfield(Pre, 'BacklogIn')
    backlog_ratio = Pre.BacklogIn / max(1, Pre.ReplayScaleN);
end
streak = 0;
if isfield(Pre, 'FullBacklogStreak')
    streak = Pre.FullBacklogStreak;
end
ratio_threshold = 0.75;
if isfield(cfg, 'overload_backlog_ratio_threshold')
    ratio_threshold = cfg.overload_backlog_ratio_threshold;
end
streak_threshold = 2;
if isfield(cfg, 'overload_full_streak_threshold')
    streak_threshold = cfg.overload_full_streak_threshold;
end
active = (backlog_ratio >= ratio_threshold) || (streak >= streak_threshold);
end

function theta = repair_and_polish(theta, Task, Fog, DNN_Data, Pre, cfg)
theta = Perform_Safe_Harbor_Repair(theta, Pre, Fog, Task, DNN_Data);
if isfield(cfg, 'enable_post_opt') && cfg.enable_post_opt
    theta = Perform_Global_Optimization(theta, Pre, Fog, Task, DNN_Data);
end
end

function tf = lexicographic_better(a, b)
tol = 1e-12;
tf = false;
for i = 1:numel(a)
    if a(i) > b(i) + tol
        tf = true;
        return;
    elseif a(i) < b(i) - tol
        return;
    end
end
end

function score = overload_candidate_score(theta, theta_ref, Task, Fog, DNN_Data, Pre, cfg)
[~, ~, b, latency, sat_vec] = calculate_metrics_v2(theta, Task, Fog, [], DNN_Data, Pre);
[~, ~, ~, ref_latency, ref_sat_vec] = calculate_metrics_v2(theta_ref, Task, Fog, [], DNN_Data, Pre);
deadline = Task(:, 3);
slack_ratio = (deadline - latency) ./ max(deadline, 1e-9);
ref_slack_ratio = (deadline - ref_latency) ./ max(deadline, 1e-9);
near_band = 0.15;
if isfield(cfg, 'overload_near_threshold_slack')
    near_band = cfg.overload_near_threshold_slack;
end
rescued = sat_vec > 0.5 & ref_sat_vec < 0.5 & slack_ratio >= -near_band & slack_ratio <= near_band;
if all(theta(:) == theta_ref(:))
    rescued = sat_vec > 0.5 & ref_slack_ratio >= -near_band & ref_slack_ratio <= near_band;
end
mem_headroom = min(b.node_mem_caps - b.node_mem);
if isempty(mem_headroom) || ~isfinite(mem_headroom)
    mem_headroom = -1e9;
end
score = [sum(sat_vec), sum(rescued), -b.spillover_block_count, ...
    -b.memory_block_count, mem_headroom, mean(sat_vec) * 100];
end

function theta = build_overload_throughput_candidate(Task, Fog, DNN_Data, Pre)
[N, M] = size(Pre.Comp);
theta = zeros(N, M);
mean_deadline = mean(Task(:, 3));
if mean_deadline < 0.1, mean_deadline = 1.0; end
mem_caps = get_node_memory_caps_local(Fog, M);
task_mem = zeros(N, 1);
for i = 1:N
    task_mem(i) = get_task_mem_mb_local(Task(i, 2), DNN_Data);
end
node_mem = zeros(1, M);
node_load = zeros(1, M);
node_count = zeros(1, M);
best_intrinsic = min(Pre.Comm + Pre.Comp, [], 2);
urgency = Task(:, 3) - best_intrinsic;
[~, order] = sortrows([urgency, Task(:, 3), best_intrinsic], [1, 2, 3]);
for idx = 1:numel(order)
    i = order(idx);
    best_f = 0;
    best_latency = inf;
    for f = 1:M
        if node_mem(f) + task_mem(i) > mem_caps(f)
            continue;
        end
        rho_new = (node_load(f) + Pre.Comp(i, f)) / mean_deadline;
        if rho_new >= 0.99
            continue;
        end
        q_new = 1 + rho_new / (2 * (1 - rho_new + 1e-6));
        ctx_new = 500e-6 * (node_count(f) + 1)^2;
        latency = Pre.Comm(i, f) + Pre.Comp(i, f) * q_new + ctx_new;
        if latency <= Task(i, 3) && latency < best_latency
            best_latency = latency;
            best_f = f;
        end
    end
    if best_f == 0
        [~, best_f] = min(Pre.Comm(i, :) + Pre.Comp(i, :));
    end
    theta(i, best_f) = 1;
    node_mem(best_f) = node_mem(best_f) + task_mem(i);
    node_load(best_f) = node_load(best_f) + Pre.Comp(i, best_f);
    node_count(best_f) = node_count(best_f) + 1;
end
end

function mem_mb = get_task_mem_mb_local(t_type, DNN_Data)
if isnumeric(DNN_Data)
    if t_type == 1
        row_idx = 3;
    elseif t_type == 2
        row_idx = 2;
    else
        row_idx = 1;
    end
    if size(DNN_Data, 1) >= row_idx && size(DNN_Data, 2) >= 2
        mem_mb = DNN_Data(row_idx, 2) + DNN_Data(row_idx, 1);
    else
        mem_mb = 100;
    end
elseif iscell(DNN_Data)
    if t_type > length(DNN_Data), t_type = 1; end
    model = DNN_Data{t_type};
    if isfield(model, 'data'), mem_mb = sum(model.data); else, mem_mb = 100; end
elseif isstruct(DNN_Data)
    if t_type > numel(DNN_Data), t_type = 1; end
    model = DNN_Data(t_type);
    if isfield(model, 'data'), mem_mb = sum(model.data); else, mem_mb = 100; end
else
    mem_mb = 100;
end
end

function mem_caps = get_node_memory_caps_local(Fog, M)
if size(Fog, 2) >= 8
    mem_caps = Fog(:, 8)';
else
    mem_caps = Fog(:, end)';
end
if numel(mem_caps) ~= M
    mem_caps = reshape(mem_caps, 1, []);
    mem_caps = mem_caps(1:min(numel(mem_caps), M));
    if numel(mem_caps) < M
        mem_caps = [mem_caps, inf(1, M - numel(mem_caps))];
    end
end
end
