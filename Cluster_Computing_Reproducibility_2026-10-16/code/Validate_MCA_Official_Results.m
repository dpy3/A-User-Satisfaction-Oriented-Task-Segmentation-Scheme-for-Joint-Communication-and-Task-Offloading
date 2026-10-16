function Validate_MCA_Official_Results(csv_path, cfg)
tbl = readtable(csv_path, 'TextType', 'string');
required = {'EvidenceClass','N','Run','Seed','Algorithm','Sat','Admission', ...
    'ResourceViolation','CompositeViolation','SatisfiedCount','TaskCount'};
assert(all(ismember(required, tbl.Properties.VariableNames)), 'MCA:MissingColumns', 'Run-level CSV lacks required columns.');
assert(height(tbl) > 0, 'MCA:EmptyResults', 'Result table is empty.');
assert(all(isfinite(tbl.Sat)) && all(tbl.Sat >= 0 & tbl.Sat <= 100), 'MCA:InvalidSat', 'Invalid satisfaction values.');
assert(all(abs(tbl.CompositeViolation - (100 - tbl.Sat)) < 1e-8), 'MCA:CompositeIdentity', 'Composite violation identity failed.');
assert(all(tbl.ResourceViolation == 0), 'MCA:ResourceViolation', 'Post-repair resource violation is nonzero.');
assert(all(tbl.SatisfiedCount <= tbl.TaskCount), 'MCA:CountBounds', 'SatisfiedCount exceeds TaskCount.');
expected_per_pair = numel(cfg.algorithms);
[groups, ~] = findgroups(tbl.N, tbl.Run, tbl.Seed);
counts = splitapply(@numel, tbl.Algorithm, groups);
assert(all(counts == expected_per_pair), 'MCA:UnpairedRuns', 'A scale/run/seed group lacks algorithms.');
for g = unique(groups)'
    names = sort(tbl.Algorithm(groups == g));
    assert(isequal(names, sort(string(cfg.algorithms(:)))), 'MCA:AlgorithmSet', 'Algorithm set differs within paired run.');
end
if ~cfg.is_manuscript_evidence
    assert(all(tbl.EvidenceClass == upper(string(cfg.mode))), 'MCA:EvidenceLabel', 'Smoke/audit evidence label mismatch.');
end
fprintf('VALIDATION PASS: %s (%d rows, %d paired environments).\n', csv_path, height(tbl), max(groups));
end
