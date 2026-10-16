function Run_Replay_Shard(scale, first_run, last_run)
arguments
    scale (1,1) double {mustBeMember(scale, [180, 300])}
    first_run (1,1) double {mustBeInteger, mustBePositive}
    last_run (1,1) double {mustBeInteger, mustBePositive}
end
assert(first_run <= last_run && last_run <= 20, 'MCA:ReplayShardRange', ...
    'Replay run range must satisfy 1 <= first <= last <= 20.');
Run_MCA_Official_Replay('selectorformal', first_run:last_run, scale);
end
