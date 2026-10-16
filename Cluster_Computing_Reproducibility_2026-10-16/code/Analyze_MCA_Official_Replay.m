function Analyze_MCA_Official_Replay(mode)
if nargin < 1 || isempty(mode), mode = 'selectorformal'; end
cfg = MCA_Official_Setup(mode);
run_path = fullfile(cfg.results_root, 'Replay_RunLevel_Merged.csv');
slot_path = fullfile(cfg.results_root, 'Replay_SlotLevel_Merged.csv');
assert(exist(run_path, 'file') == 2 && exist(slot_path, 'file') == 2, ...
    'MCA:ReplayMergedMissing', 'Merge complete replay shards before analysis.');
run_tbl = readtable(run_path, 'TextType', 'string');
slot_tbl = readtable(slot_path, 'TextType', 'string');
Validate_MCA_Official_Replay(slot_tbl, run_tbl, cfg, true);

summary_rows = repmat(summary_template(), 0, 1);
for N = cfg.replay_scales(:)'
    for alg = string(cfg.algorithms(:))'
        block = run_tbl(run_tbl.N == N & run_tbl.Algorithm == alg, :);
        summary_rows(end + 1) = make_summary(N, alg, block); %#ok<AGROW>
    end
end
summary_tbl = struct2table(summary_rows);
writetable(summary_tbl, fullfile(cfg.results_root, 'Replay_Summary_Official.csv'));

metrics = ["MeanSat", "TotalSatisfied", "BacklogAUC", "QueueCapDrops"];
primary = string(cfg.primary_algorithm);
comparators = setdiff(string(cfg.algorithms(:))', primary, 'stable');
pair_rows = repmat(pair_template(), 0, 1);
rng(cfg.seed_base + 780, 'twister');
for N = cfg.replay_scales(:)'
    alm = ordered(run_tbl, N, primary);
    for comparator = comparators
        other = ordered(run_tbl, N, comparator);
        assert(isequal(alm.Run, other.Run), 'MCA:ReplayUnpaired', 'Run mismatch at N=%d.', N);
        for metric = metrics
            if ismember(metric, ["BacklogAUC", "QueueCapDrops"])
                d = other.(metric) - alm.(metric); % Positive means ALM is better.
            else
                d = alm.(metric) - other.(metric);
            end
            pair_rows(end + 1) = make_pair(N, primary, comparator, metric, d); %#ok<AGROW>
        end
    end
end
pair_tbl = struct2table(pair_rows);
pair_tbl.PHolm = holm_adjust(pair_tbl.PSignFlip);
writetable(pair_tbl, fullfile(cfg.results_root, 'Replay_ALM_Paired.csv'));
save(fullfile(cfg.results_root, 'Replay_Official_Analysis.mat'), 'summary_tbl', 'pair_tbl', 'cfg');
disp(summary_tbl); disp(pair_tbl);
end

function block = ordered(tbl, N, algorithm)
block = sortrows(tbl(tbl.N == N & tbl.Algorithm == algorithm, :), 'Run');
end

function row = summary_template()
row = struct('N', 0, 'Algorithm', "", 'Runs', 0, 'MeanSat', 0, ...
    'TotalSatisfiedMean', 0, 'BacklogAUCMean', 0, 'PeakBacklogMean', 0, ...
    'QueueCapDropsMean', 0, 'MeanRuntimeSec', 0);
end

function row = make_summary(N, alg, block)
row = summary_template(); row.N = N; row.Algorithm = alg; row.Runs = height(block);
row.MeanSat = mean(block.MeanSat); row.TotalSatisfiedMean = mean(block.TotalSatisfied);
row.BacklogAUCMean = mean(block.BacklogAUC); row.PeakBacklogMean = mean(block.PeakBacklog);
row.QueueCapDropsMean = mean(block.QueueCapDrops); row.MeanRuntimeSec = mean(block.MeanRuntimeSec);
end

function row = pair_template()
row = struct('N', 0, 'PrimaryAlgorithm', "", 'Comparator', "", 'Metric', "", 'Runs', 0, ...
    'MeanAdvantageALM', 0, 'CI95Low', 0, 'CI95High', 0, 'PairedCohenDz', 0, ...
    'Wins', 0, 'Ties', 0, 'Losses', 0, 'PSignFlip', 0);
end

function row = make_pair(N, primary, comparator, metric, d)
row = pair_template(); row.N = N; row.PrimaryAlgorithm = primary; row.Comparator = comparator; row.Metric = metric; row.Runs = numel(d);
row.MeanAdvantageALM = mean(d); sd = std(d); half = 1.96 * sd / sqrt(numel(d));
row.CI95Low = mean(d) - half; row.CI95High = mean(d) + half;
if sd > 1e-12, row.PairedCohenDz = mean(d) / sd; end
row.Wins = sum(d > 0); row.Ties = sum(d == 0); row.Losses = sum(d < 0);
row.PSignFlip = signflip_pvalue(d, 20000);
end

function p = signflip_pvalue(d, B)
d = d(:); if all(abs(d) < eps), p = 1; return; end
observed = abs(mean(d)); hits = 0;
for b = 1:B
    signs = 2 * (rand(size(d)) > 0.5) - 1;
    hits = hits + (abs(mean(d .* signs)) >= observed - 1e-12);
end
p = (hits + 1) / (B + 1);
end

function adjusted = holm_adjust(raw)
[sorted, order] = sort(raw); m = numel(raw); temp = zeros(m, 1);
for i = 1:m, temp(i) = min(1, (m - i + 1) * sorted(i)); end
for i = 2:m, temp(i) = max(temp(i), temp(i - 1)); end
adjusted = zeros(m, 1); adjusted(order) = temp;
end
