function Run_SelectorV9_Calibration_Shard(scale, first_run, last_run)
arguments
    scale (1,1) double {mustBeMember(scale, [240, 270, 300])}
    first_run (1,1) double {mustBeInteger, mustBePositive}
    last_run (1,1) double {mustBeInteger, mustBePositive}
end
assert(first_run <= last_run, 'MCA:ReplayShardRange', 'first_run must be <= last_run.');
assert(first_run >= 6 && last_run <= 10, 'MCA:SelectorV9CalibrationLeakage', ...
    'Calibration is restricted to runs 6:10.');
Run_MCA_Official_Replay('selectorv9calibration', first_run:last_run, scale);
end
