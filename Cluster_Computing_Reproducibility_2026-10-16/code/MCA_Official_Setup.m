function cfg = MCA_Official_Setup(mode)
cfg = MCA_Official_Config(mode);
root = cfg.code_root;

% Remove the incompatible legacy metric implementation if it was loaded.
legacy = fullfile(root, 'Legacy_Root');
if contains(path, legacy), rmpath(legacy); end
addpath(root, '-begin');
addpath(fullfile(root, 'Algorithms'), '-begin');
addpath(fullfile(root, 'Environment'), '-begin');
addpath(fullfile(root, 'Data'), '-begin');
addpath(fullfile(root, 'Utils'), '-begin');
addpath(fileparts(mfilename('fullpath')), '-begin');

expected_metric = fullfile(root, 'Utils', 'calculate_metrics_v2.m');
actual_metric = which('calculate_metrics_v2');
if ~strcmpi(actual_metric, expected_metric)
    error('MCA:MetricPathDrift', 'Expected metric %s, resolved %s', expected_metric, actual_metric);
end
if ~exist(cfg.results_root, 'dir'), mkdir(cfg.results_root); end
end
