function state = MCA_MultiResource_State(Task, Fog, Thing, DNN_Data, backlog_count, scale_N)
Pre = build_pre_struct_tier1(Task, Fog, Thing, DNN_Data);
[N, M] = size(Pre.Comp);
intrinsic = Pre.Comp + Pre.Comm;
[~, assignment] = min(intrinsic, [], 2);
mean_deadline = max(mean(Task(:, 3)), 1e-9);
compute = zeros(1, M); memory = zeros(1, M); link = zeros(1, M);
for i = 1:N
    f = assignment(i);
    compute(f) = compute(f) + Pre.Comp(i, f) / mean_deadline;
    link(f) = link(f) + Pre.Comm(i, f) / max(Task(i, 3), 1e-9);
    memory(f) = memory(f) + task_memory(Task(i, 2), DNN_Data);
end
if size(Fog, 2) >= 8, memory_caps = Fog(:, 8)'; else, memory_caps = Fog(:, end)'; end
compute_pressure = max(compute);
memory_pressure = max(memory ./ max(memory_caps, 1));
% Link pressure is normalized by the number of tasks mapped to a node so
% that it expresses deadline occupancy rather than raw task count.
counts = accumarray(assignment, 1, [M, 1])';
link_pressure = max(link ./ max(counts, 1));
queue_pressure = backlog_count / max(1, scale_N);
intrinsic_feasible = any(intrinsic <= Task(:, 3), 2);
% Version-2 controllers compare resources through action-specific joint
% service gains instead of heterogeneous raw pressure magnitudes.  Every
% candidate must improve deadline and memory feasibility on the same node.
full_factor = 1.25; half_factor = 1.125;
deadline = Task(:, 3);
memory_need = zeros(N, 1);
for i = 1:N, memory_need(i) = task_memory(Task(i, 2), DNN_Data); end
[base_feasible,base_utility]=joint_utility(Pre.Comp,Pre.Comm,memory_caps, ...
    memory_need,deadline);
[compute_full,compute_full_u]=joint_utility(Pre.Comp/full_factor,Pre.Comm, ...
    memory_caps,memory_need,deadline);
[compute_half,compute_half_u]=joint_utility(Pre.Comp/half_factor,Pre.Comm, ...
    memory_caps,memory_need,deadline);
[memory_full,memory_full_u]=joint_utility(Pre.Comp,Pre.Comm, ...
    memory_caps*full_factor,memory_need,deadline);
[memory_half,memory_half_u]=joint_utility(Pre.Comp,Pre.Comm, ...
    memory_caps*half_factor,memory_need,deadline);
[link_full,link_full_u]=joint_utility(Pre.Comp,Pre.Comm/full_factor, ...
    memory_caps,memory_need,deadline);
[link_half,link_half_u]=joint_utility(Pre.Comp,Pre.Comm/half_factor, ...
    memory_caps,memory_need,deadline);
exact_full=[rescue_fraction(base_feasible,compute_full), ...
    rescue_fraction(base_feasible,memory_full),rescue_fraction(base_feasible,link_full)];
exact_half=[rescue_fraction(base_feasible,compute_half), ...
    rescue_fraction(base_feasible,memory_half),rescue_fraction(base_feasible,link_half)];
soft_full=[mean(compute_full_u-base_utility),mean(memory_full_u-base_utility), ...
    mean(link_full_u-base_utility)];
soft_half=[mean(compute_half_u-base_utility),mean(memory_half_u-base_utility), ...
    mean(link_half_u-base_utility)];
raw_pressure=[compute_pressure,memory_pressure,link_pressure];
aggregate_full=arrayfun(@(x) capacity_utility_gain(x,full_factor),raw_pressure);
aggregate_half=arrayfun(@(x) capacity_utility_gain(x,half_factor),raw_pressure);
deadline_feasible=mean(any(intrinsic<=deadline,2));
memory_feasible=mean(any(memory_need<=memory_caps,2));
complementary_mask=[memory_feasible,deadline_feasible,memory_feasible];
masked_full=aggregate_full.*complementary_mask;
masked_half=aggregate_half.*complementary_mask;
action_gain_full=max(max(max(exact_full,0),max(soft_full,0)),masked_full);
action_gain_half=max(max(max(exact_half,0),max(soft_half,0)),masked_half);
state = struct('ComputePressure',compute_pressure,'MemoryPressure',memory_pressure, ...
    'BandwidthPressure',link_pressure,'QueuePressure',queue_pressure, ...
    'IntrinsicInfeasibleFraction',mean(~intrinsic_feasible), ...
    'Vector',[compute_pressure,memory_pressure,link_pressure,queue_pressure], ...
    'ImmediateRescueFull',max(exact_full,0), ...
    'ImmediateRescueHalf',max(exact_half,0), ...
    'JointUtilityGainFull',max(soft_full,0), ...
    'JointUtilityGainHalf',max(soft_half,0), ...
    'MaskedCapacityGainFull',masked_full, ...
    'MaskedCapacityGainHalf',masked_half, ...
    'ActionGainFull',action_gain_full,'ActionGainHalf',action_gain_half, ...
    'ArrivalFraction',min(1,scale_N/max(1,N)));
end

function [feasible,utility]=joint_utility(comp,comm,memory_caps,memory_need,deadline)
latency=comp+comm;
deadline_score=min(1,deadline./max(latency,1e-9));
memory_score=min(1,memory_caps./max(memory_need,1e-9));
joint_score=min(deadline_score,memory_score);
utility=max(joint_score,[],2);
feasible=any(latency<=deadline & memory_need<=memory_caps,2);
end

function value=rescue_fraction(base_feasible,action_feasible)
value=mean(action_feasible & ~base_feasible);
end

function gain=capacity_utility_gain(pressure,factor)
base=min(1,1/max(pressure,1e-9));
boosted=min(1,factor/max(pressure,1e-9));
gain=max(0,boosted-base);
end

function value = task_memory(task_type, DNN_Data)
if iscell(DNN_Data) && task_type <= numel(DNN_Data) && isfield(DNN_Data{task_type}, 'data')
    value = sum(DNN_Data{task_type}.data);
elseif isnumeric(DNN_Data)
    map=[3,2,1]; row=map(min(max(round(task_type),1),3));
    value=sum(DNN_Data(row,1:min(2,size(DNN_Data,2))));
else
    value=100;
end
end
