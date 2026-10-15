function Analyze_MCA_Official_Baselines(mode)
if nargin < 1 || isempty(mode), mode = 'baselineformal'; end
cfg = MCA_Official_Setup(mode);
input_path = fullfile(cfg.results_root, 'Static_RunLevel.csv');
tbl = readtable(input_path, 'TextType', 'string');
Validate_MCA_Official_Results(input_path, cfg);
assert(height(tbl) == numel(cfg.static_scales) * cfg.runs * numel(cfg.algorithms), ...
    'MCA:IncompleteBaselines', 'Formal baseline table is incomplete.');
validate_main_reproduction(tbl, cfg);

comparators = ["Greedy", "GAHybrid", "LPRelax", "DPP", "MPC"];
rows = repmat(pair_template(), 0, 1);
rng(cfg.seed_base + 779, 'twister');
for N = cfg.static_scales(:)'
    alm = ordered_block(tbl, N, "ALM");
    for comparator = comparators
        other = ordered_block(tbl, N, comparator);
        assert(isequal(alm.Seed, other.Seed), 'MCA:UnpairedBaseline', 'Seed mismatch at N=%d.', N);
        rows(end + 1) = make_pair(N, comparator, alm.Sat - other.Sat); %#ok<AGROW>
    end
end
pair_tbl = struct2table(rows);
pair_tbl.PHolm = holm_adjust(pair_tbl.PSignFlip);
writetable(pair_tbl, fullfile(cfg.results_root, 'Static_ALM_vs_AllBaselines_Paired.csv'));
save(fullfile(cfg.results_root, 'Static_Baseline_Analysis.mat'), 'pair_tbl', 'cfg');
disp(pair_tbl);
end

function block = ordered_block(tbl, N, algorithm)
block = sortrows(tbl(tbl.N == N & tbl.Algorithm == algorithm, :), 'Seed');
end

function validate_main_reproduction(tbl, cfg)
main_path = fullfile(fileparts(cfg.results_root), 'SELECTORFORMAL_FIXED5', 'Static_RunLevel.csv');
main = readtable(main_path, 'TextType', 'string');
for alg = ["Greedy", "GAHybrid", "ALM"]
    a = sortrows(main(main.Algorithm == alg & ismember(main.N, cfg.static_scales), :), {'N','Seed'});
    b = sortrows(tbl(tbl.Algorithm == alg, :), {'N','Seed'});
    assert(isequal(a.N, b.N) && isequal(a.Seed, b.Seed), 'MCA:BaselineSeedDrift', ...
        '%s does not use the main environments.', alg);
    for field = {"Sat","Admission","SatisfiedCount","AdmittedCount"}
        assert(all(abs(a.(field{1}) - b.(field{1})) < 1e-10), 'MCA:BaselineReproduction', ...
            '%s differs from SELECTORFORMAL in %s.', alg, field{1});
    end
end
fprintf('REPRODUCTION PASS: Greedy, GAHybrid, and ALM match SELECTORFORMAL on all congested rows.\n');
end

function row = pair_template()
row = struct('N', 0, 'Comparator', "", 'Runs', 0, 'MeanDiffALMMinusComparator', 0, ...
    'DiffCI95Low', 0, 'DiffCI95High', 0, 'PairedCohenDz', 0, ...
    'Wins', 0, 'Ties', 0, 'Losses', 0, 'PSignFlip', 0);
end

function row = make_pair(N, comparator, d)
row = pair_template(); row.N = N; row.Comparator = comparator; row.Runs = numel(d);
row.MeanDiffALMMinusComparator = mean(d); sd = std(d);
half = 1.96 * sd / sqrt(numel(d));
row.DiffCI95Low = mean(d) - half; row.DiffCI95High = mean(d) + half;
if sd > 1e-12, row.PairedCohenDz = mean(d) / sd; end
row.Wins = sum(d > 0); row.Ties = sum(d == 0); row.Losses = sum(d < 0);
row.PSignFlip = signflip_pvalue(d, 20000);
end

function p = signflip_pvalue(d, B)
d = d(:);
if all(abs(d) < eps), p = 1; return; end
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
