function Run_SelectorV9_Formal_Shard(scale, first_run, last_run)
arguments
    scale (1,1) double {mustBeMember(scale, [240, 270, 300])}
    first_run (1,1) double {mustBeInteger, mustBePositive}
    last_run (1,1) double {mustBeInteger, mustBePositive}
end
assert(first_run <= last_run, 'MCA:ReplayShardRange', 'first_run must be <= last_run.');
assert(first_run >= 11 && last_run <= 30, 'MCA:SelectorV9FormalLeakage', ...
    'Formal selector-v9 testing is restricted to held-out runs 11:30.');
Run_MCA_Official_Replay('selectorv9formal', first_run:last_run, scale);
end
