function Run_MCA_Capacity_Phase_Shard(profile, first_run, last_run, mode)
if nargin < 3
    error('Usage: Run_MCA_Capacity_Phase_Shard(profile, first_run, last_run, [mode])');
end
if nargin < 4 || isempty(mode), mode = 'capacityphasepilot'; end
Run_MCA_Capacity_Phase(mode, first_run:last_run, {char(profile)}, []);
end
