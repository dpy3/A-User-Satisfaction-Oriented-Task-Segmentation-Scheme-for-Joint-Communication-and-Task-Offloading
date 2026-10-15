% MERGE_FINAL_RESULTS
%
% Merges Batch 1 and Batch 2 results into a single 'results_scale_final.mat'
% and generates publication figures.
%
% Usage:
%   merge_final_results

clc; clear; close all;

RESULTS_DIR = 'Results_Final_Publication';
BATCH1_FILE = fullfile(RESULTS_DIR, 'results_part1.mat');
BATCH2_FILE = fullfile(RESULTS_DIR, 'results_part2.mat');
BATCH1_CP = fullfile(RESULTS_DIR, 'results_batch_1_checkpoint.mat');
BATCH2_CP = fullfile(RESULTS_DIR, 'results_batch_2_checkpoint.mat');
FINAL_FILE = fullfile(RESULTS_DIR, 'results_scale_final.mat');

fprintf('Checking for batch files...\n');

% Try to load Final files first, then Checkpoints
use_checkpoint = false;
if exist(BATCH1_FILE, 'file') && exist(BATCH2_FILE, 'file')
    fprintf('Loading completed batch files...\n');
    data1 = load(BATCH1_FILE);
    data2 = load(BATCH2_FILE);
elseif exist(BATCH1_CP, 'file') && exist(BATCH2_CP, 'file')
    fprintf('Batch files not done. Loading CHECKPOINTS instead...\n');
    data1 = load(BATCH1_CP);
    data2 = load(BATCH2_CP);
    use_checkpoint = true;
else
    error('Neither final files nor checkpoints found!');
end

% Verify structures
if ~isequal(data1.N_RANGE, data2.N_RANGE)
    error('Mismatch in N_RANGE between batches!');
end

% Handle missing ALGORITHMS field
if isfield(data1, 'ALGORITHMS')
    ALGORITHMS = data1.ALGORITHMS;
else
    ALGORITHMS = {'Local', 'Greedy', 'GA', 'GA-Hybrid', 'Memetic-ALM'};
    fprintf('Warning: ALGORITHMS field missing in batch files. Using default.\n');
end

results_scale = struct();
results_scale.sat = data1.results_scale.sat + data2.results_scale.sat;
results_scale.lat = data1.results_scale.lat + data2.results_scale.lat;
results_scale.viol = data1.results_scale.viol + data2.results_scale.viol;
results_scale.time = data1.results_scale.time + data2.results_scale.time;
N_RANGE = data1.N_RANGE;
% ALGORITHMS is already set above

% Calculate Statistics for N=100
n_idx_100 = find(N_RANGE == 100);
if ~isempty(n_idx_100)
    fprintf('\n=== N=100 Statistics (Partial/Full) ===\n');
    for a = 1:length(ALGORITHMS)
        % Filter out zero entries (unrun)
        sats = results_scale.sat(n_idx_100, a, :);
        valid_idx = sats > 0;
        
        if any(valid_idx)
            mean_sat = mean(sats(valid_idx));
            mean_viol = mean(results_scale.viol(n_idx_100, a, valid_idx));
            mean_lat = mean(results_scale.lat(n_idx_100, a, valid_idx));
            count = sum(valid_idx);
            
            fprintf('%-15s (n=%d): Sat=%.2f%%, Viol=%.2f%%, Lat=%.4fs\n', ALGORITHMS{a}, count, mean_sat, mean_viol*100, mean_lat);
        else
            fprintf('%-15s (n=0): N/A\n', ALGORITHMS{a});
        end
    end
    fprintf('==================================\n');
end

% Save Final
save(FINAL_FILE, 'results_scale', 'N_RANGE', 'ALGORITHMS');
fprintf('Merged results saved to %s\n', FINAL_FILE);

% Generate Figures
fprintf('Generating Publication Figures...\n');
try
    plot_publication_figures;
catch ME
    fprintf('Error generating figures: %s\n', ME.message);
end

fprintf('Done.\n');
