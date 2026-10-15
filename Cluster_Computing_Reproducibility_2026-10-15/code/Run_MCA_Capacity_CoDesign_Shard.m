function Run_MCA_Capacity_CoDesign_Shard(profile, first_run, last_run, mode)
if nargin < 3
    error('Usage: Run_MCA_Capacity_CoDesign_Shard(profile, first_run, last_run, [mode])');
end
if nargin < 4 || isempty(mode), mode = 'capacitycodesignpilot'; end
Run_MCA_Capacity_CoDesign(mode, first_run:last_run, {char(profile)}, []);
end
