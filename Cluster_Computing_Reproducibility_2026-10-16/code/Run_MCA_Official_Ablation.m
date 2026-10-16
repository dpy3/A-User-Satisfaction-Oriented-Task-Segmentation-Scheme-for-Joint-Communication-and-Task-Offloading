function Run_MCA_Official_Ablation(mode, scale_indices, run_indices)
if nargin < 1 || isempty(mode), mode = 'ablationsmoke'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'ablation'), 'MCA:WrongMode', ...
    'Ablation runner requires an ablation mode.');
if nargin < 2 || isempty(scale_indices), scale_indices = 1:numel(cfg.static_scales); end
if nargin < 3 || isempty(run_indices), run_indices = 1:cfg.runs; end
assert(all(ismember(scale_indices, 1:numel(cfg.static_scales))), 'MCA:ScaleIndex', 'Invalid scale index.');
assert(all(ismember(run_indices, 1:cfg.runs)), 'MCA:RunIndex', 'Invalid run index.');

suffix = shard_suffix(scale_indices, run_indices, cfg);
checkpoint = fullfile(cfg.results_root, ['Ablation_Checkpoint' suffix '.mat']);
output_path = fullfile(cfg.results_root, ['Ablation_RunLevel' suffix '.csv']);
MCA_Write_Manifest(cfg, {mfilename('fullpath'), which('MCA_Solve')});

rows = repmat(base_row(), 0, 1);
if exist(checkpoint, 'file')
    saved = load(checkpoint, 'rows');
    rows = saved.rows;
end

fprintf('MCA ablation %s: scales=%s, runs=%s\n', upper(cfg.mode), ...
    mat2str(cfg.static_scales(scale_indices)), mat2str(run_indices));
for n_idx = scale_indices(:)'
    N = cfg.static_scales(n_idx);
    for run = run_indices(:)'
        seed_idx = find(cfg.seed_scale_reference == N, 1);
        assert(~isempty(seed_idx), 'MCA:SeedScaleReference', 'N=%d lacks a seed-scale reference.', N);
        seed = cfg.seed_base + 100000 * seed_idx + run;
        if is_complete(rows, N, run, seed, cfg.algorithms), continue; end
        rng(seed, 'twister');
        [Task, Fog, Thing, DNN_Data, Pre] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
        Pre.Mean_Deadline = mean(Task(:, 3));
        Pre.Violation_Mode = cfg.violation_mode;
        rows = remove_partial(rows, N, run, seed);
        for a = 1:numel(cfg.algorithms)
            alg = cfg.algorithms{a};
            % Common random numbers isolate the two algorithmic factors.
            % Match the ALM stream in Run_MCA_Official_Static so ALMFull is
            % an exact per-seed reproduction of the SELECTORFORMAL method.
            rng(seed + 3000, 'twister');
            t0 = tic;
            theta = MCA_Solve(alg, Task, Fog, Thing, DNN_Data, Pre, cfg);
            runtime = toc(t0);
            m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
                sprintf('ablation/N%d/R%d/%s', N, run, alg));
            assert(m.ResourceViolation == 0, 'MCA:PostRepairResourceViolation', ...
                'N=%d run=%d %s has resource violation.', N, run, alg);
            rows(end + 1) = make_row(cfg, N, run, seed, alg, runtime, m); %#ok<AGROW>
            fprintf('N=%d run=%d %s Sat=%.2f Runtime=%.3fs\n', N, run, alg, m.Sat, runtime);
        end
        save(checkpoint, 'rows', 'cfg', 'scale_indices', 'run_indices');
    end
end

tbl = struct2table(rows);
writetable(tbl, output_path);
Validate_MCA_Official_Results(output_path, cfg);
fprintf('ABLATION %s PASS: %s\n', upper(cfg.mode), output_path);
end

function tf = is_complete(rows, N, run, seed, algorithms)
if isempty(rows), tf = false; return; end
mask = [rows.N] == N & [rows.Run] == run & [rows.Seed] == seed;
names = sort(string({rows(mask).Algorithm}));
tf = isequal(names(:), sort(string(algorithms(:))));
end

function rows = remove_partial(rows, N, run, seed)
if isempty(rows), return; end
mask = [rows.N] == N & [rows.Run] == run & [rows.Seed] == seed;
rows(mask) = [];
end

function suffix = shard_suffix(scale_indices, run_indices, cfg)
if isequal(scale_indices(:)', 1:numel(cfg.static_scales)) && isequal(run_indices(:)', 1:cfg.runs)
    suffix = '';
else
    suffix = sprintf('_S%s_R%d-%d', strjoin(string(scale_indices), '-'), min(run_indices), max(run_indices));
end
end

function row = base_row()
row = struct('SchemaVersion', "", 'EvidenceClass', "", 'N', 0, 'FogNodes', 0, ...
    'Run', 0, 'Seed', 0, 'Algorithm', "", 'GuardedAcceptance', false, ...
    'RepairAwareRanking', false, 'Sat', 0, 'Admission', 0, ...
    'TimelyAmongAdmitted', 0, 'ResourceViolation', 0, 'DeadlineViolation', 0, ...
    'CompositeViolation', 0, 'InvalidAssignment', 0, 'LatencyAdmitted', 0, ...
    'LatencyTimely', 0, 'SatisfiedCount', 0, 'AdmittedCount', 0, ...
    'TaskCount', 0, 'RuntimeSec', 0);
end

function row = make_row(cfg, N, run, seed, alg, runtime, m)
row = base_row();
row.SchemaVersion = string(cfg.schema_version); row.EvidenceClass = upper(string(cfg.mode));
row.N = N; row.FogNodes = cfg.fog_num_fixed; row.Run = run; row.Seed = seed;
row.Algorithm = string(alg);
row.GuardedAcceptance = ismember(upper(alg), {'ALMGUARDED', 'ALMFULL'});
row.RepairAwareRanking = ismember(upper(alg), {'ALMREPAIRAWARE', 'ALMFULL'});
fields = {'Sat','Admission','TimelyAmongAdmitted','ResourceViolation','DeadlineViolation', ...
    'CompositeViolation','InvalidAssignment','LatencyAdmitted','LatencyTimely', ...
    'SatisfiedCount','AdmittedCount','TaskCount'};
for i = 1:numel(fields), row.(fields{i}) = m.(fields{i}); end
row.RuntimeSec = runtime;
end
