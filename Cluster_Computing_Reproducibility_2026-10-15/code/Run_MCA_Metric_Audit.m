function Run_MCA_Metric_Audit()
cfg = MCA_Official_Setup('audit');
MCA_Write_Manifest(cfg, {mfilename('fullpath')});
fprintf('MCA official metric audit: %s\n', cfg.schema_version);
fprintf('Metric implementation: %s\n', which('calculate_metrics_v2'));

rows = repmat(base_row(), 0, 1);
for n_idx = 1:numel(cfg.static_scales)
    N = cfg.static_scales(n_idx);
    fog_num = resolve_fog_num(N, cfg);
    seed = cfg.seed_base + n_idx;
    rng(seed, 'twister');
    [Task, Fog, Thing, DNN_Data, Pre] = generate_tier1_env_trace(N, fog_num);
    Pre.Mean_Deadline = mean(Task(:, 3));
    Pre.Violation_Mode = cfg.violation_mode;
    for a = 1:numel(cfg.algorithms)
        alg = cfg.algorithms{a};
        rng(seed + 1000 * a, 'twister');
        t0 = tic;
        theta = MCA_Solve(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
        runtime = toc(t0);
        m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, sprintf('audit/N%d/%s', N, alg));
        assert(m.ResourceViolation == 0, 'MCA:PostRepairResourceViolation', ...
            'N=%d %s has %.6f%% resource violation after repair.', N, alg, m.ResourceViolation);
        rows(end + 1) = make_row(cfg, N, 1, seed, alg, runtime, m); %#ok<AGROW>
    end
end

tbl = struct2table(rows);
writetable(tbl, fullfile(cfg.results_root, 'Metric_Audit_RunLevel.csv'));
save(fullfile(cfg.results_root, 'Metric_Audit.mat'), 'tbl', 'cfg');
disp(tbl(:, {'N','Algorithm','Sat','Admission','ResourceViolation','CompositeViolation'}));
fprintf('AUDIT PASS: %d algorithm-runs validated.\n', height(tbl));
end

function row = base_row()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, 'Run', 0, 'Seed', 0, ...
    'Algorithm', "", 'Sat', 0, 'Admission', 0, 'TimelyAmongAdmitted', 0, ...
    'ResourceViolation', 0, 'DeadlineViolation', 0, 'CompositeViolation', 0, ...
    'InvalidAssignment', 0, 'LatencyAdmitted', 0, 'LatencyTimely', 0, ...
    'SatisfiedCount', 0, 'AdmittedCount', 0, 'TaskCount', 0, 'RuntimeSec', 0);
end

function row = make_row(cfg, N, run, seed, alg, runtime, m)
row = base_row();
row.SchemaVersion = string(cfg.schema_version);
row.EvidenceClass = upper(string(cfg.mode));
row.N = N; row.Run = run; row.Seed = seed; row.Algorithm = string(alg);
fields = {'Sat','Admission','TimelyAmongAdmitted','ResourceViolation','DeadlineViolation', ...
    'CompositeViolation','InvalidAssignment','LatencyAdmitted','LatencyTimely', ...
    'SatisfiedCount','AdmittedCount','TaskCount'};
for i = 1:numel(fields), row.(fields{i}) = m.(fields{i}); end
row.RuntimeSec = runtime;
end

function fog_num = resolve_fog_num(N, cfg)
if strcmpi(cfg.fog_mode, 'fixed')
    fog_num = cfg.fog_num_fixed;
else
    fog_num = max(cfg.min_fog_nodes, round(N / cfg.fog_divisor));
end
end
