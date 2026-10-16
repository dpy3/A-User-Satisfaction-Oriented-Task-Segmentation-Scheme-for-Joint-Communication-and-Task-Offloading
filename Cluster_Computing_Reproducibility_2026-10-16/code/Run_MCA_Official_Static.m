function Run_MCA_Official_Static(mode)
if nargin < 1, mode = 'smoke'; end
cfg = MCA_Official_Setup(mode);
MCA_Write_Manifest(cfg, {mfilename('fullpath')});
rows = repmat(base_row(), 0, 1);
checkpoint = fullfile(cfg.results_root, 'Static_Checkpoint.mat');

fprintf('MCA static %s: scales=%s, runs=%d\n', upper(cfg.mode), mat2str(cfg.static_scales), cfg.runs);
for n_idx = 1:numel(cfg.static_scales)
    N = cfg.static_scales(n_idx);
    fog_num = resolve_fog_num(N, cfg);
    for run = 1:cfg.runs
        seed_idx = find(cfg.seed_scale_reference == N, 1);
        assert(~isempty(seed_idx), 'MCA:SeedScaleReference', 'N=%d lacks a seed-scale reference.', N);
        seed = cfg.seed_base + 100000 * seed_idx + run;
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
            m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, sprintf('static/N%d/R%d/%s', N, run, alg));
            assert(m.ResourceViolation == 0, 'MCA:PostRepairResourceViolation', ...
                'N=%d run=%d %s has resource violation.', N, run, alg);
            rows(end + 1) = make_row(cfg, N, run, seed, fog_num, alg, runtime, m); %#ok<AGROW>
            fprintf('N=%d run=%d %s Sat=%.2f Adm=%.2f Runtime=%.3fs\n', ...
                N, run, alg, m.Sat, m.Admission, runtime);
        end
        save(checkpoint, 'rows', 'cfg');
    end
end

tbl = struct2table(rows);
run_path = fullfile(cfg.results_root, 'Static_RunLevel.csv');
writetable(tbl, run_path);
save(fullfile(cfg.results_root, 'Static_Results.mat'), 'tbl', 'cfg');
Validate_MCA_Official_Results(run_path, cfg);
fprintf('STATIC %s PASS: %d paired algorithm-runs.\n', upper(cfg.mode), height(tbl));
end

function row = base_row()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, 'FogNodes', 0, ...
    'Run', 0, 'Seed', 0, 'Algorithm', "", 'Sat', 0, 'Admission', 0, ...
    'TimelyAmongAdmitted', 0, 'ResourceViolation', 0, 'DeadlineViolation', 0, ...
    'CompositeViolation', 0, 'InvalidAssignment', 0, 'LatencyAdmitted', 0, ...
    'LatencyTimely', 0, 'SatisfiedCount', 0, 'AdmittedCount', 0, ...
    'TaskCount', 0, 'RuntimeSec', 0);
end

function row = make_row(cfg, N, run, seed, fog_num, alg, runtime, m)
row = base_row();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.N = N; row.FogNodes = fog_num; row.Run = run; row.Seed = seed; row.Algorithm = string(alg);
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
