function Analyze_MCA_Official_Ablation(mode)
if nargin < 1 || isempty(mode), mode = 'ablationformal'; end
cfg = MCA_Official_Setup(mode);
input_path = fullfile(cfg.results_root, 'Ablation_RunLevel.csv');
assert(exist(input_path, 'file') == 2, 'MCA:MissingAblation', ...
    'Canonical ablation CSV is missing: %s', input_path);
tbl = readtable(input_path, 'TextType', 'string');
Validate_MCA_Official_Results(input_path, cfg);
assert(height(tbl) == numel(cfg.static_scales) * cfg.runs * numel(cfg.algorithms), ...
    'MCA:IncompleteAblation', 'Formal ablation is incomplete.');
validate_main_reproduction(tbl, cfg);

summary_rows = repmat(summary_template(), 0, 1);
for N = cfg.static_scales(:)'
    for a = 1:numel(cfg.algorithms)
        alg = string(cfg.algorithms{a});
        block = tbl(tbl.N == N & tbl.Algorithm == alg, :);
        summary_rows(end + 1) = make_summary(N, alg, block); %#ok<AGROW>
    end
end
summary_tbl = struct2table(summary_rows);
writetable(summary_tbl, fullfile(cfg.results_root, 'Ablation_Summary.csv'));

pair_rows = repmat(pair_template(), 0, 1);
rng(cfg.seed_base + 778, 'twister');
comparators = ["ALMRaw", "ALMGuarded", "ALMRepairAware"];
for N = cfg.static_scales(:)'
    full = ordered_block(tbl, N, "ALMFull");
    for comparator = comparators
        other = ordered_block(tbl, N, comparator);
        assert(isequal(full.Seed, other.Seed), 'MCA:UnpairedAblation', 'Seed mismatch at N=%d.', N);
        pair_rows(end + 1) = make_pair(N, comparator, full.Sat - other.Sat); %#ok<AGROW>
    end
end
pair_tbl = struct2table(pair_rows);
pair_tbl.PHolm = holm_adjust(pair_tbl.PSignFlip);
writetable(pair_tbl, fullfile(cfg.results_root, 'Ablation_Full_Paired.csv'));

effect_rows = repmat(effect_template(), 0, 1);
for N = cfg.static_scales(:)'
    raw = ordered_block(tbl, N, "ALMRaw").Sat;
    guard = ordered_block(tbl, N, "ALMGuarded").Sat;
    repair = ordered_block(tbl, N, "ALMRepairAware").Sat;
    full = ordered_block(tbl, N, "ALMFull").Sat;
    guard_effect = 0.5 * ((guard - raw) + (full - repair));
    repair_effect = 0.5 * ((repair - raw) + (full - guard));
    interaction = full - guard - repair + raw;
    effect_rows(end + 1) = make_effect(N, guard_effect, repair_effect, interaction); %#ok<AGROW>
end
effect_tbl = struct2table(effect_rows);
writetable(effect_tbl, fullfile(cfg.results_root, 'Ablation_Factorial_Effects.csv'));
save(fullfile(cfg.results_root, 'Ablation_Official_Analysis.mat'), ...
    'summary_tbl', 'pair_tbl', 'effect_tbl', 'cfg');
disp(summary_tbl); disp(pair_tbl); disp(effect_tbl);
end

function validate_main_reproduction(tbl, cfg)
if ~strcmpi(cfg.mode, 'ablationformal'), return; end
main_path = fullfile(fileparts(cfg.results_root), 'SELECTORFORMAL_FIXED5', 'Static_RunLevel.csv');
assert(exist(main_path, 'file') == 2, 'MCA:MissingMainEvidence', ...
    'SELECTORFORMAL evidence is required for ablation reproduction validation.');
main = readtable(main_path, 'TextType', 'string');
main = sortrows(main(main.Algorithm == "ALM" & ismember(main.N, cfg.static_scales), :), {'N','Seed'});
full = sortrows(tbl(tbl.Algorithm == "ALMFull", :), {'N','Seed'});
assert(isequal(main.N, full.N) && isequal(main.Seed, full.Seed), ...
    'MCA:AblationSeedDrift', 'ALMFull does not use the main experiment environments.');
fields = {'Sat','Admission','SatisfiedCount','AdmittedCount','CompositeViolation'};
for i = 1:numel(fields)
    assert(all(abs(main.(fields{i}) - full.(fields{i})) < 1e-10), ...
        'MCA:AblationReproduction', 'ALMFull differs from SELECTORFORMAL in %s.', fields{i});
end
fprintf('REPRODUCTION PASS: ALMFull exactly matches SELECTORFORMAL ALM on %d rows.\n', height(full));
end

function block = ordered_block(tbl, N, algorithm)
block = sortrows(tbl(tbl.N == N & tbl.Algorithm == algorithm, :), 'Seed');
end

function row = summary_template()
row = struct('N', 0, 'Algorithm', "", 'Runs', 0, 'SatMean', 0, 'SatSD', 0, ...
    'SatCI95Low', 0, 'SatCI95High', 0, 'RuntimeMeanSec', 0);
end

function row = make_summary(N, alg, block)
row = summary_template(); row.N = N; row.Algorithm = alg; row.Runs = height(block);
row.SatMean = mean(block.Sat); row.SatSD = std(block.Sat);
half = 1.96 * row.SatSD / sqrt(row.Runs);
row.SatCI95Low = max(0, row.SatMean - half); row.SatCI95High = min(100, row.SatMean + half);
row.RuntimeMeanSec = mean(block.RuntimeSec);
end

function row = pair_template()
row = struct('N', 0, 'Comparator', "", 'Runs', 0, 'MeanDiffFullMinusComparator', 0, ...
    'DiffCI95Low', 0, 'DiffCI95High', 0, 'PairedCohenDz', 0, ...
    'Wins', 0, 'Ties', 0, 'Losses', 0, 'PSignFlip', 0);
end

function row = make_pair(N, comparator, d)
row = pair_template(); row.N = N; row.Comparator = comparator; row.Runs = numel(d);
row.MeanDiffFullMinusComparator = mean(d); sd = std(d);
half = 1.96 * sd / sqrt(numel(d));
row.DiffCI95Low = mean(d) - half; row.DiffCI95High = mean(d) + half;
if sd > 1e-12, row.PairedCohenDz = mean(d) / sd; end
row.Wins = sum(d > 0); row.Ties = sum(d == 0); row.Losses = sum(d < 0);
row.PSignFlip = signflip_pvalue(d, 20000);
end

function row = effect_template()
row = struct('N', 0, 'Runs', 0, 'GuardMainEffectMean', 0, ...
    'RepairAwareMainEffectMean', 0, 'InteractionMean', 0);
end

function row = make_effect(N, guard_effect, repair_effect, interaction)
row = effect_template(); row.N = N; row.Runs = numel(guard_effect);
row.GuardMainEffectMean = mean(guard_effect);
row.RepairAwareMainEffectMean = mean(repair_effect);
row.InteractionMean = mean(interaction);
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
