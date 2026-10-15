function Analyze_MCA_Official_Static(mode)
if nargin < 1, mode = 'formal'; end
cfg = MCA_Official_Setup(mode);
input_path = fullfile(cfg.results_root, 'Static_RunLevel.csv');
tbl = readtable(input_path, 'TextType', 'string');
scales = unique(tbl.N, 'stable');
algorithms = unique(tbl.Algorithm, 'stable');
summary_rows = repmat(summary_template(), 0, 1);

for n_idx = 1:numel(scales)
    N = scales(n_idx);
    for a = 1:numel(algorithms)
        alg = algorithms(a);
        block = tbl(tbl.N == N & tbl.Algorithm == alg, :);
        summary_rows(end + 1) = make_summary(N, alg, block); %#ok<AGROW>
    end
end
summary_tbl = struct2table(summary_rows);
writetable(summary_tbl, fullfile(cfg.results_root, 'Static_Summary_Official.csv'));

pair_rows = repmat(pair_template(), 0, 1);
rng(cfg.seed_base + 777, 'twister');
for n_idx = 1:numel(scales)
    N = scales(n_idx);
    ga = sortrows(tbl(tbl.N == N & tbl.Algorithm == "GAHybrid", :), {'Seed'});
    alm = sortrows(tbl(tbl.N == N & tbl.Algorithm == "ALM", :), {'Seed'});
    assert(isequal(ga.Seed, alm.Seed), 'MCA:UnpairedStats', 'Seed mismatch at N=%d.', N);
    diff_sat = alm.Sat - ga.Sat;
    pair_rows(end + 1) = make_pair(N, diff_sat, alm.RuntimeSec, ga.RuntimeSec); %#ok<AGROW>
end
pair_tbl = struct2table(pair_rows);
pair_tbl.PHolm = holm_adjust(pair_tbl.PSignFlip);
writetable(pair_tbl, fullfile(cfg.results_root, 'Static_ALM_vs_GAHybrid_Paired.csv'));
save(fullfile(cfg.results_root, 'Static_Official_Analysis.mat'), 'summary_tbl', 'pair_tbl', 'cfg');
disp(pair_tbl);
end

function row = summary_template()
row = struct('N', 0, 'Algorithm', "", 'Runs', 0, 'SatMean', 0, 'SatSD', 0, ...
    'SatCI95Low', 0, 'SatCI95High', 0, 'AdmissionMean', 0, ...
    'RuntimeMeanSec', 0, 'RuntimeSD', 0);
end

function row = make_summary(N, alg, block)
row = summary_template(); row.N = N; row.Algorithm = alg; row.Runs = height(block);
row.SatMean = mean(block.Sat); row.SatSD = std(block.Sat);
half = 1.96 * row.SatSD / sqrt(row.Runs);
row.SatCI95Low = row.SatMean - half; row.SatCI95High = row.SatMean + half;
row.AdmissionMean = mean(block.Admission); row.RuntimeMeanSec = mean(block.RuntimeSec);
row.RuntimeSD = std(block.RuntimeSec);
end

function row = pair_template()
row = struct('N', 0, 'Runs', 0, 'MeanDiffSat_ALMminusGA', 0, ...
    'DiffCI95Low', 0, 'DiffCI95High', 0, 'PairedCohenDz', 0, ...
    'Wins', 0, 'Ties', 0, 'Losses', 0, 'PSignFlip', 0, 'PHolm', 0, ...
    'MeanRuntimeRatio_ALMtoGA', 0);
end

function row = make_pair(N, diff_sat, alm_runtime, ga_runtime)
row = pair_template(); row.N = N; row.Runs = numel(diff_sat);
row.MeanDiffSat_ALMminusGA = mean(diff_sat);
sd = std(diff_sat); half = 1.96 * sd / sqrt(row.Runs);
row.DiffCI95Low = row.MeanDiffSat_ALMminusGA - half;
row.DiffCI95High = row.MeanDiffSat_ALMminusGA + half;
if sd == 0, row.PairedCohenDz = 0; else, row.PairedCohenDz = row.MeanDiffSat_ALMminusGA / sd; end
row.Wins = sum(diff_sat > 0); row.Ties = sum(diff_sat == 0); row.Losses = sum(diff_sat < 0);
row.PSignFlip = signflip_pvalue(diff_sat, 20000);
row.MeanRuntimeRatio_ALMtoGA = mean(alm_runtime) / max(eps, mean(ga_runtime));
end

function p = signflip_pvalue(diff_values, B)
diff_values = diff_values(:);
if all(abs(diff_values) < eps), p = 1; return; end
observed = abs(mean(diff_values));
hits = 0;
for b = 1:B
    signs = 2 * (rand(size(diff_values)) > 0.5) - 1;
    hits = hits + (abs(mean(diff_values .* signs)) >= observed - 1e-12);
end
p = (hits + 1) / (B + 1);
end

function adjusted = holm_adjust(raw)
[sorted, order] = sort(raw);
m = numel(raw); temp = zeros(m, 1);
for i = 1:m, temp(i) = min(1, (m - i + 1) * sorted(i)); end
for i = 2:m, temp(i) = max(temp(i), temp(i - 1)); end
adjusted = zeros(m, 1); adjusted(order) = temp;
end
