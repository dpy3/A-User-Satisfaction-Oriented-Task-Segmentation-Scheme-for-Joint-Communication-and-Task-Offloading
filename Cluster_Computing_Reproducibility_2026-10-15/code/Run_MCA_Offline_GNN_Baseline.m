function Run_MCA_Offline_GNN_Baseline(mode)
if nargin < 1 || isempty(mode), mode = 'smoke'; end
cfg = MCA_Official_Setup('baselineformal');
protocol = offline_config(mode, cfg);
if ~exist(protocol.results_dir, 'dir'), mkdir(protocol.results_dir); end
model_path = fullfile(protocol.results_dir, 'OfflineGNN_Frozen_Model.mat');
manifest_files = {mfilename('fullpath'), which('Bipartite_GNN_Solver_Binary'), ...
    fullfile(fileparts(mfilename('fullpath')), 'OFFLINE_GNN_PROTOCOL.md')};
MCA_Write_Manifest(set_results_root(cfg, protocol.results_dir), manifest_files);

if exist(model_path, 'file') ~= 2
    candidates = cell(numel(protocol.learning_rates), 1);
    validation = zeros(numel(candidates), 1);
    for c = 1:numel(candidates)
        rng(protocol.train_seed + c, 'twister');
        params = [];
        for N = protocol.train_scales
            for run = protocol.train_runs
                [Task, Fog, Thing, DNN_Data, Pre] = official_environment(cfg, N, run);
                gcfg = gnn_config(protocol, protocol.learning_rates(c));
                gcfg.GNN_PRETRAINED_PARAMS = params;
                gcfg.GNN_TRAIN_ONLY = true;
                [~, params] = Bipartite_GNN_Solver_Binary(Task, Fog, Thing, DNN_Data, Pre, gcfg);
            end
        end
        candidates{c} = params;
        validation(c) = validate_model(params, protocol, cfg);
        fprintf('OfflineGNN candidate %d validation satisfaction %.4f\n', c, validation(c));
    end
    [~, selected_index] = max(validation);
    frozen_params = candidates{selected_index};
    selected_learning_rate = protocol.learning_rates(selected_index);
    save(model_path, 'frozen_params', 'selected_index', 'selected_learning_rate', ...
        'validation', 'protocol', 'cfg');
else
    saved = load(model_path, 'frozen_params', 'protocol');
    frozen_params = saved.frozen_params;
end

rows = repmat(base_row(), 0, 1);
checkpoint = fullfile(protocol.results_dir, 'OfflineGNN_Test_Checkpoint.mat');
if exist(checkpoint, 'file') == 2
    saved = load(checkpoint, 'rows'); rows = saved.rows;
end
for N = protocol.test_scales
    for run = protocol.test_runs
        if any([rows.N] == N & [rows.Run] == run), continue; end
        [Task, Fog, Thing, DNN_Data, Pre, seed] = official_environment(cfg, N, run);
        gcfg = gnn_config(protocol, 0);
        gcfg.GNN_PRETRAINED_PARAMS = frozen_params;
        gcfg.GNN_SKIP_TRAINING = true;
        rng(protocol.test_inference_seed + seed, 'twister');
        t0 = tic;
        theta = Bipartite_GNN_Solver_Binary(Task, Fog, Thing, DNN_Data, Pre, gcfg);
        runtime = toc(t0);
        theta = Perform_Safe_Harbor_Repair(theta, Pre, Fog, Task, DNN_Data);
        theta = Perform_Global_Optimization(theta, Pre, Fog, Task, DNN_Data);
        m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, ...
            sprintf('offline-gnn/N%d/R%d', N, run));
        assert(m.ResourceViolation == 0, 'GNN:PostRepairViolation', ...
            'OfflineGNN resource violation at N=%d run=%d.', N, run);
        rows(end + 1) = make_row(protocol, N, run, seed, runtime, m); %#ok<AGROW>
        save(checkpoint, 'rows', 'protocol');
        fprintf('OfflineGNN N=%d run=%d Sat=%.2f Runtime=%.3fs\n', N, run, m.Sat, runtime);
    end
end
output = fullfile(protocol.results_dir, 'OfflineGNN_Test_RunLevel.csv');
writetable(struct2table(rows), output);
analyze_results(output, protocol, cfg);
fprintf('OFFLINE GNN BASELINE PASS: %s\n', output);
end

function protocol = offline_config(mode, cfg)
protocol.mode = lower(char(mode));
protocol.learning_rates = [0.02, 0.04];
protocol.train_seed = 2026072851;
protocol.test_inference_seed = 9000000;
protocol.train_scales = [120, 180, 250, 300];
protocol.validation_scales = [120, 180, 250, 300];
protocol.test_scales = [120, 150, 180, 200, 250, 300];
switch protocol.mode
    case 'smoke'
        protocol.train_runs = 51; protocol.validation_runs = 61;
        protocol.test_runs = 1:2; protocol.epochs_per_environment = 1;
    case 'formal'
        protocol.train_runs = 51:55; protocol.validation_runs = 61:63;
        protocol.test_runs = 1:30; protocol.epochs_per_environment = 4;
    otherwise
        error('GNN:UnknownOfflineMode', 'Unknown mode: %s', mode);
end
protocol.results_dir = fullfile(fileparts(mfilename('fullpath')), 'Results', ...
    ['OFFLINEGNN_' upper(protocol.mode) '_FIXED5']);
protocol.schema_version = 'MCA-OFFICIAL-1.9-OFFLINE-GNN';
protocol.official_seed_base = cfg.seed_base;
end

function gcfg = gnn_config(protocol, learning_rate)
gcfg = struct('GNN_HIDDEN_DIM',24,'GNN_EPOCHS',protocol.epochs_per_environment, ...
    'GNN_LEARNING_RATE',max(learning_rate,0.02),'GNN_WARMSTART_ROLLOUTS',1, ...
    'GNN_WARMSTART_EPS',0.05,'GNN_DAGGER_ITERS',0,'GNN_MASK_DEADLINE_MARGIN',1.02, ...
    'GNN_SKIP_TRAINING',false,'GNN_TRAIN_ONLY',false);
end

function score = validate_model(params, protocol, cfg)
values = zeros(numel(protocol.validation_scales) * numel(protocol.validation_runs), 1);
cursor = 0;
for N = protocol.validation_scales
    for run = protocol.validation_runs
        [Task, Fog, Thing, DNN_Data, Pre] = official_environment(cfg, N, run);
        gcfg = gnn_config(protocol, 0); gcfg.GNN_PRETRAINED_PARAMS = params;
        gcfg.GNN_SKIP_TRAINING = true;
        theta = Bipartite_GNN_Solver_Binary(Task, Fog, Thing, DNN_Data, Pre, gcfg);
        theta = Perform_Safe_Harbor_Repair(theta, Pre, Fog, Task, DNN_Data);
        theta = Perform_Global_Optimization(theta, Pre, Fog, Task, DNN_Data);
        m = MCA_Evaluate(theta, Task, Fog, Thing, DNN_Data, Pre, 'offline-gnn-validation');
        cursor = cursor + 1; values(cursor) = m.Sat;
    end
end
score = mean(values);
end

function [Task, Fog, Thing, DNN_Data, Pre, seed] = official_environment(cfg, N, run)
idx = find(cfg.seed_scale_reference == N, 1);
assert(~isempty(idx), 'GNN:SeedScaleReference', 'N=%d lacks seed mapping.', N);
seed = cfg.seed_base + 100000 * idx + run;
rng(seed, 'twister');
[Task, Fog, Thing, DNN_Data, Pre] = generate_tier1_env_trace(N, cfg.fog_num_fixed);
Pre.Mean_Deadline = mean(Task(:,3)); Pre.Violation_Mode = cfg.violation_mode;
end

function cfg = set_results_root(cfg, value)
cfg.results_root = value;
end

function row = base_row()
row = struct('SchemaVersion',"",'EvidenceClass',"",'N',0,'Run',0,'Seed',0, ...
    'Algorithm',"OfflineGNN",'Sat',0,'Admission',0,'ResourceViolation',0, ...
    'CompositeViolation',0,'SatisfiedCount',0,'TaskCount',0,'RuntimeSec',0);
end

function row = make_row(protocol, N, run, seed, runtime, m)
row = base_row(); row.SchemaVersion = string(protocol.schema_version);
row.EvidenceClass = upper(string(protocol.mode)); row.N=N; row.Run=run; row.Seed=seed;
row.Sat=m.Sat; row.Admission=m.Admission; row.ResourceViolation=m.ResourceViolation;
row.CompositeViolation=m.CompositeViolation; row.SatisfiedCount=m.SatisfiedCount;
row.TaskCount=m.TaskCount; row.RuntimeSec=runtime;
end

function analyze_results(path, protocol, cfg)
tbl = readtable(path, 'TextType', 'string');
expected = numel(protocol.test_scales) * numel(protocol.test_runs);
assert(height(tbl) == expected, 'GNN:IncompleteOfflineTest', ...
    'Expected %d test rows, found %d.', expected, height(tbl));
assert(all(tbl.ResourceViolation == 0), 'GNN:ResourceViolation', ...
    'OfflineGNN contains post-repair violations.');
summary = groupsummary(tbl, 'N', {'mean','std'}, {'Sat','RuntimeSec'});
writetable(summary, fullfile(protocol.results_dir, 'OfflineGNN_Test_Summary.csv'));
main_path = fullfile(fileparts(cfg.results_root), 'BASELINEFORMAL_FIXED5', 'Static_RunLevel.csv');
if exist(main_path, 'file') ~= 2, return; end
main = readtable(main_path, 'TextType', 'string');
alm = sortrows(main(main.Algorithm == "ALM" & ismember(main.N, protocol.test_scales) & ...
    ismember(main.Run, protocol.test_runs), :), {'N','Run'});
learned = sortrows(tbl, {'N','Run'});
assert(isequal(alm.N, learned.N) && isequal(alm.Run, learned.Run) && isequal(alm.Seed, learned.Seed), ...
    'GNN:OfficialPairing', 'OfflineGNN test rows do not match official ALM environments.');
paired = table(learned.N, learned.Run, learned.Seed, alm.Sat - learned.Sat, ...
    'VariableNames', {'N','Run','Seed','ALMMinusOfflineGNN'});
writetable(paired, fullfile(protocol.results_dir, 'OfflineGNN_ALM_Paired.csv'));
end
