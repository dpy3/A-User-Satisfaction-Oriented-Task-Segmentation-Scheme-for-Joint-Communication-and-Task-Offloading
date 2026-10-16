function Analyze_MCA_Repair_Transfer(mode)
if nargin < 1 || isempty(mode), mode = 'repairtransferformal'; end
cfg = MCA_Official_Setup(mode);
assert(startsWith(cfg.mode, 'repairtransfer'), 'MCA:WrongMode', ...
    'Repair-transfer analysis requires a repair-transfer mode.');
input_path = fullfile(cfg.results_root, 'RepairTransfer_RunLevel.csv');
assert(exist(input_path, 'file') == 2, 'MCA:MissingRepairTransfer', ...
    'Canonical repair-transfer CSV is missing: %s', input_path);
tbl = readtable(input_path, 'TextType', 'string');
Validate_MCA_Official_Results(input_path, cfg);
validate_complete(tbl, cfg);

families = ["GAHybrid", "ALM"];
scale_rows = repmat(pair_template(), 0, 1);
for N = cfg.static_scales(:)'
    for family = families
        d = paired_difference(tbl(tbl.N == N, :), family);
        scale_rows(end + 1) = make_pair(N, family, d, ...
            cfg.seed_base + 7100 + N + numel(scale_rows)); %#ok<AGROW>
    end
end
scale_tbl = struct2table(scale_rows);
scale_tbl.PHolm = holm_adjust(scale_tbl.PSignFlip);
writetable(scale_tbl, fullfile(cfg.results_root, 'RepairTransfer_ByScale.csv'));

primary_rows = repmat(primary_template(), 0, 1);
for family = families
    run_effect = zeros(numel(cfg.required_static_runs), 1);
    for i = 1:numel(cfg.required_static_runs)
        run = cfg.required_static_runs(i);
        run_effect(i) = mean(paired_difference(tbl(tbl.Run == run, :), family));
    end
    primary_rows(end + 1) = make_primary(family, run_effect, ...
        numel(cfg.static_scales), cfg.seed_base + 8100 + numel(primary_rows)); %#ok<AGROW>
end
primary_tbl = struct2table(primary_rows);
primary_tbl.PHolm = holm_adjust(primary_tbl.PSignFlip);
primary_tbl.Supported = primary_tbl.MeanDiffAwareMinusRaw > 0 & ...
    primary_tbl.DiffCI95Low > 0 & primary_tbl.PHolm < 0.05;

ga_supported = primary_tbl.Supported(primary_tbl.OptimizerFamily == "GAHybrid");
assert(isscalar(ga_supported), 'MCA:GAGate', 'GA primary row is missing or duplicated.');
if ga_supported
    transfer_status = "SUPPORTED: independent GA-family gate passed";
else
    transfer_status = "NOT SUPPORTED: do not claim cross-algorithm portability";
end
primary_tbl.TransferClaimStatus(:) = transfer_status;
writetable(primary_tbl, fullfile(cfg.results_root, 'RepairTransfer_FamilyPrimary.csv'));
save(fullfile(cfg.results_root, 'RepairTransfer_Official_Analysis.mat'), ...
    'scale_tbl', 'primary_tbl', 'cfg', 'transfer_status');
disp(scale_tbl);
disp(primary_tbl);
fprintf('%s\n', transfer_status);
end

function validate_complete(tbl, cfg)
expected = numel(cfg.static_scales) * numel(cfg.required_static_runs) * numel(cfg.algorithms);
assert(height(tbl) == expected, 'MCA:IncompleteRepairTransfer', ...
    'Expected %d rows, found %d.', expected, height(tbl));
assert(isequal(sort(unique(tbl.Run))', sort(cfg.required_static_runs)), ...
    'MCA:RepairTransferRunSet', 'Run set differs from the frozen protocol.');
assert(isequal(sort(unique(tbl.N))', sort(cfg.static_scales)), ...
    'MCA:RepairTransferScaleSet', 'Scale set differs from the frozen protocol.');
assert(all(tbl.OptimizerFamily == "GAHybrid" | tbl.OptimizerFamily == "ALM"), ...
    'MCA:RepairTransferFamily', 'Unexpected optimizer family.');
for family = ["GAHybrid", "ALM"]
    block = tbl(tbl.OptimizerFamily == family, :);
    [groups, ~] = findgroups(block.N, block.Run);
    counts = splitapply(@numel, block.Algorithm, groups);
    assert(all(counts == 2), 'MCA:RepairTransferPair', ...
        '%s raw/repair-aware pairs are incomplete.', family);
    flags = splitapply(@sum, double(block.RepairAwareRanking), groups);
    assert(all(flags == 1), 'MCA:RepairTransferFactor', ...
        '%s groups must contain exactly one repair-aware arm.', family);
end
end

function d = paired_difference(tbl, family)
aware = sortrows(tbl(tbl.OptimizerFamily == family & tbl.RepairAwareRanking, :), {'N','Run'});
raw = sortrows(tbl(tbl.OptimizerFamily == family & ~tbl.RepairAwareRanking, :), {'N','Run'});
assert(height(aware) == height(raw) && isequal(aware.N, raw.N) && ...
    isequal(aware.Run, raw.Run) && isequal(aware.Seed, raw.Seed), ...
    'MCA:UnpairedRepairTransfer', '%s rows are not paired.', family);
d = aware.Sat - raw.Sat;
end

function row = pair_template()
row = struct('N', 0, 'OptimizerFamily', "", 'Pairs', 0, ...
    'MeanDiffAwareMinusRaw', 0, 'DiffCI95Low', 0, 'DiffCI95High', 0, ...
    'PairedCohenDz', 0, 'Wins', 0, 'Ties', 0, 'Losses', 0, 'PSignFlip', 0);
end

function row = make_pair(N, family, d, bootstrap_seed)
base = summarize_difference(d, bootstrap_seed);
row = pair_template();
row.N = N;
row.OptimizerFamily = family;
row.Pairs = numel(d);
fields = fieldnames(base);
for i = 1:numel(fields), row.(fields{i}) = base.(fields{i}); end
end

function row = primary_template()
row = struct('OptimizerFamily', "", 'IndependentRuns', 0, 'ScalesPerRun', 0, ...
    'MeanDiffAwareMinusRaw', 0, 'DiffCI95Low', 0, 'DiffCI95High', 0, ...
    'PairedCohenDz', 0, 'Wins', 0, 'Ties', 0, 'Losses', 0, ...
    'PSignFlip', 0, 'PHolm', 0, 'Supported', false, 'TransferClaimStatus', "");
end

function row = make_primary(family, d, scales, bootstrap_seed)
base = summarize_difference(d, bootstrap_seed);
row = primary_template();
row.OptimizerFamily = family;
row.IndependentRuns = numel(d);
row.ScalesPerRun = scales;
fields = fieldnames(base);
for i = 1:numel(fields), row.(fields{i}) = base.(fields{i}); end
end

function out = summarize_difference(d, bootstrap_seed)
d = d(:);
out = struct();
out.MeanDiffAwareMinusRaw = mean(d);
[out.DiffCI95Low, out.DiffCI95High] = bootstrap_ci(d, bootstrap_seed, 20000);
sd = std(d);
out.PairedCohenDz = 0;
if sd > 1e-12, out.PairedCohenDz = mean(d) / sd; end
tol = 1e-10;
out.Wins = sum(d > tol);
out.Ties = sum(abs(d) <= tol);
out.Losses = sum(d < -tol);
out.PSignFlip = signflip_pvalue(d);
end

function [low, high] = bootstrap_ci(d, seed, B)
if isscalar(d), low = d; high = d; return; end
rng(seed, 'twister');
indices = randi(numel(d), numel(d), B);
boot = sort(mean(d(indices), 1));
low = boot(max(1, round(0.025 * B)));
high = boot(min(B, round(0.975 * B)));
end

function p = signflip_pvalue(d)
d = d(:);
if all(abs(d) < eps), p = 1; return; end
n = numel(d);
if n <= 20
    total = 2^n;
    observed = abs(mean(d));
    hits = 0;
    batch_size = 65536;
    for first = 0:batch_size:(total - 1)
        last = min(total - 1, first + batch_size - 1);
        ids = uint32((first:last)');
        signs = ones(numel(ids), n);
        for j = 1:n, signs(:, j) = 2 * double(bitget(ids, j)) - 1; end
        hits = hits + sum(abs((signs * d) / n) >= observed - 1e-12);
    end
    p = hits / total;
else
    B = 100000;
    signs = 2 * (rand(n, B) > 0.5) - 1;
    p = (sum(abs(mean(d .* signs, 1)) >= abs(mean(d)) - 1e-12) + 1) / (B + 1);
end
end

function adjusted = holm_adjust(raw)
[sorted, order] = sort(raw);
m = numel(raw);
temp = zeros(m, 1);
for i = 1:m, temp(i) = min(1, (m - i + 1) * sorted(i)); end
for i = 2:m, temp(i) = max(temp(i), temp(i - 1)); end
adjusted = zeros(m, 1);
adjusted(order) = temp;
end
