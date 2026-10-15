function Merge_MCA_MultiResource_Control_Shards(mode)
if nargin<1 || isempty(mode),mode='pilot';end
root=fileparts(mfilename('fullpath'));
result_dir=fullfile(root,'Results',['MULTIRESOURCE_' upper(char(mode))]);
shard_root=fullfile(result_dir,'SHARDS');
files=dir(fullfile(shard_root,'*','MultiResource_Control_RunLevel.csv'));
assert(~isempty(files),'MCA:NoMRShards','No completed multi-resource shards under %s.',shard_root);

merged=table();
for i=1:numel(files)
    part=readtable(fullfile(files(i).folder,files(i).name),'TextType','string');
    merged=[merged;part]; %#ok<AGROW>
end
keys=strcat(merged.Profile,"|",string(merged.Run),"|",merged.Policy);
assert(numel(unique(keys))==height(merged),'MCA:DuplicateMRShardRows', ...
    'Multi-resource shards contain duplicate profile/run/policy keys.');

profiles=["compute_bound","memory_bound","latency_filtered"];
if strcmpi(mode,'pilot3')
    profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    policies=["NoAction","FixedMatchedV2","MPCMRV2","LyapunovMRv2"];
    runs=(11:15)'; expected_slots=100;
elseif strcmpi(mode,'pilot4')
    profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    policies=["NoAction","FixedMatchedV2","MPCMRV2","LyapunovMRv3"];
    runs=(16:20)'; expected_slots=100;
elseif strcmpi(mode,'smoke4')
    profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    policies=["NoAction","FixedMatchedV2","MPCMRV2","LyapunovMRv2"];
    runs=(201:202)'; expected_slots=20;
elseif strcmpi(mode,'smoke5')
    profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    policies=["NoAction","FixedMatchedV2","MPCMRV2","LyapunovMRv2"];
    runs=(203:204)'; expected_slots=20;
elseif strcmpi(mode,'smoke6')
    profiles=["compute_bound","memory_bound","latency_comm_isolated_v3"];
    policies=["NoAction","FixedMatchedV2","MPCMRV2","LyapunovMRv3"];
    runs=(205:206)'; expected_slots=20;
elseif strcmpi(mode,'pilot2')
    policies=["NoAction","FixedMatched","MPCMR","LyapunovMR"];
    runs=(6:10)'; expected_slots=100;
else
    policies=["NoAction","FixedMatched","MPCMR","LyapunovMR"];
    runs=(1:5)'; expected_slots=100;
end
for profile=profiles
    for policy=policies
        part=sortrows(merged(merged.Profile==profile & merged.Policy==policy,:),'Run');
        assert(isequal(part.Run,runs),'MCA:IncompleteMRPilotShard', ...
            'Expected frozen runs for %s/%s.',profile,policy);
        assert(all(part.Slots==expected_slots),'MCA:MRPilotSlotDrift', ...
            'Expected %d slots for %s/%s.',expected_slots,profile,policy);
    end
end
expected_rows=numel(profiles)*numel(runs)*numel(policies);
assert(height(merged)==expected_rows,'MCA:MRPilotRowCount', ...
    'Expected %d rows, found %d.',expected_rows,height(merged));
merged=sortrows(merged,{'Profile','Run','Policy'});
writetable(merged,fullfile(result_dir,'MultiResource_Control_RunLevel.csv'));
fprintf('MULTI-RESOURCE PILOT SHARDS MERGED: %d rows -> %s\n',height(merged),result_dir);
end
