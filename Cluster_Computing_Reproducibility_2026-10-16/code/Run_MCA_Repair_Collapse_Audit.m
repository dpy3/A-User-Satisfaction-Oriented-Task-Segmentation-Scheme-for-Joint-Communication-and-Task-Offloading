function Run_MCA_Repair_Collapse_Audit()
cfg = MCA_Official_Setup('pilot');
cfg.enable_repair = false;
cfg.enable_post_opt = false;
N = 150;
runs = 5;
algorithms = cfg.algorithms;
stages = {'Raw', 'Repair', 'PostOpt'};
metric_rows = repmat(metric_template(), 0, 1);
pair_rows = repmat(pair_template(), 0, 1);
MCA_Write_Manifest(cfg, {mfilename('fullpath')});

for run = 1:runs
    seed = cfg.seed_base + 900000 + run;
    rng(seed, 'twister');
    [Task, Fog, Thing, DNN_Data, Pre] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
    Pre.Mean_Deadline = mean(Task(:, 3));
    Pre.Violation_Mode = cfg.violation_mode;
    stage_theta = struct();
    stage_metrics = struct();
    for a = 1:numel(algorithms)
        alg = algorithms{a};
        rng(seed + 1000 * a, 'twister');
        theta_raw = solve_raw(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
        theta_repair = Perform_Safe_Harbor_Repair(theta_raw, Pre, Fog, Task, DNN_Data);
        theta_post = Perform_Global_Optimization(theta_repair, Pre, Fog, Task, DNN_Data);
        values = {theta_raw, theta_repair, theta_post};
        for s = 1:numel(stages)
            stage = stages{s};
            theta = values{s};
            m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
                sprintf('collapse/R%d/%s/%s', run, alg, stage));
            stage_theta.(stage).(alg) = theta;
            stage_metrics.(stage).(alg) = m;
            metric_rows(end + 1) = make_metric(run, seed, alg, stage, m); %#ok<AGROW>
        end
    end
    for s = 1:numel(stages)
        stage = stages{s};
        ga_theta = stage_theta.(stage).GAHybrid;
        alm_theta = stage_theta.(stage).ALM;
        ga_m = stage_metrics.(stage).GAHybrid;
        alm_m = stage_metrics.(stage).ALM;
        ga_node = decode_assignment(ga_theta);
        alm_node = decode_assignment(alm_theta);
        agreement = mean(ga_node == alm_node) * 100;
        sat_jaccard = binary_jaccard(ga_m.SatisfiedVector, alm_m.SatisfiedVector);
        pair_rows(end + 1) = make_pair(run, seed, stage, agreement, sat_jaccard, ga_m, alm_m); %#ok<AGROW>
    end
end

metric_tbl = struct2table(metric_rows);
pair_tbl = struct2table(pair_rows);
writetable(metric_tbl, fullfile(cfg.results_root, 'Repair_Collapse_StageMetrics.csv'));
writetable(pair_tbl, fullfile(cfg.results_root, 'Repair_Collapse_GA_vs_ALM.csv'));
save(fullfile(cfg.results_root, 'Repair_Collapse_Audit.mat'), 'metric_tbl', 'pair_tbl', 'cfg');
summary = groupsummary(pair_tbl, 'Stage', 'mean', ...
    {'AssignmentAgreementPct','SatisfiedSetJaccard','AbsSatisfiedCountGap'});
writetable(summary, fullfile(cfg.results_root, 'Repair_Collapse_Summary.csv'));
disp(summary);
fprintf('COLLAPSE AUDIT PASS: %d stage metrics and %d paired comparisons.\n', height(metric_tbl), height(pair_tbl));
end

function theta = solve_raw(alg, Task, Fog, Thing, DNN_Data, Pre, cfg)
switch upper(alg)
    case 'GREEDY'
        theta = Greedy_Solver_DNN(Task, Fog, Thing, DNN_Data, Pre);
    case 'GAHYBRID'
        opts = struct('use_greedy_seed', true, 'seed_fraction', cfg.ga_seed_fraction, ...
            'seed_mutation_fraction', cfg.ga_mutation_fraction, 'apply_final_repair', false);
        [theta, ~] = GA_Solver_DNN_Vectorized(Task, Fog, Thing, DNN_Data, ...
            cfg.ga_pop, cfg.ga_gen, Pre, opts);
    case 'ALM'
        params = alm_params(N_of(Task));
        [theta, ~, ~] = M_CA_ALM_Solver(Task, Fog, Thing, DNN_Data, ...
            cfg.alm_max_iter, [], [], params, false, Pre);
    otherwise
        error('MCA:UnknownAlgorithm', 'Unknown algorithm: %s', alg);
end
end

function value = N_of(Task)
value = size(Task, 1);
end

function params = alm_params(N)
params = struct('lr', 0.05, 'rho', 1.0, 'mu', 1.05, 'alpha', 0.1, ...
    'pop_size', 20, 'deadline_scale', 1.0);
if N >= 100
    params.lr = 0.1; params.rho = 0.01; params.alpha = 0.8;
    params.pop_size = 50; params.deadline_scale = 0.85;
end
end

function node = decode_assignment(theta)
[best, node] = max(theta, [], 2);
node(best <= 0) = 0;
end

function value = binary_jaccard(a, b)
a = a > 0; b = b > 0;
den = sum(a | b);
if den == 0, value = 100; else, value = 100 * sum(a & b) / den; end
end

function row = metric_template()
row = struct('N', 0, 'Run', 0, 'Seed', 0, 'Algorithm', "", 'Stage', "", ...
    'Sat', 0, 'SatisfiedCount', 0, 'Admission', 0, 'ResourceViolation', 0, ...
    'DeadlineViolation', 0, 'CompositeViolation', 0);
end

function row = make_metric(run, seed, alg, stage, m)
row = metric_template(); row.N = m.TaskCount; row.Run = run; row.Seed = seed;
row.Algorithm = string(alg); row.Stage = string(stage); row.Sat = m.Sat;
row.SatisfiedCount = m.SatisfiedCount; row.Admission = m.Admission;
row.ResourceViolation = m.ResourceViolation; row.DeadlineViolation = m.DeadlineViolation;
row.CompositeViolation = m.CompositeViolation;
end

function row = pair_template()
row = struct('N', 0, 'Run', 0, 'Seed', 0, 'Stage', "", ...
    'AssignmentAgreementPct', 0, 'SatisfiedSetJaccard', 0, ...
    'GASatisfiedCount', 0, 'ALMSatisfiedCount', 0, 'AbsSatisfiedCountGap', 0);
end

function row = make_pair(run, seed, stage, agreement, jaccard, ga, alm)
row = pair_template(); row.N = ga.TaskCount; row.Run = run; row.Seed = seed; row.Stage = string(stage);
row.AssignmentAgreementPct = agreement; row.SatisfiedSetJaccard = jaccard;
row.GASatisfiedCount = ga.SatisfiedCount; row.ALMSatisfiedCount = alm.SatisfiedCount;
row.AbsSatisfiedCountGap = abs(ga.SatisfiedCount - alm.SatisfiedCount);
end
