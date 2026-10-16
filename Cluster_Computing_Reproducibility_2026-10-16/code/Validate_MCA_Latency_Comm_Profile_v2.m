function Validate_MCA_Latency_Comm_Profile_v2()
% Validate the frozen profile at its capacity-normalized pilot load.
mode='capacityphaselatencyv2final2';
cfg=MCA_Official_Setup(mode);
capacity_file=fullfile(cfg.results_root,'Capacity_Reference_Frozen.csv');
assert(exist(capacity_file,'file')==2,'MCA:LatencyV2CapacityMissing', ...
    'Run the v2 capacity calibration before profile validation.');
capacity=readtable(capacity_file,'TextType','string');
row=capacity(capacity.Profile=="latency_comm_v2",:);
assert(height(row)==1,'MCA:LatencyV2CapacityRow','Expected one frozen capacity row.');
lambda=0.55; N=max(1,round(row.CapacityRef(1)*lambda)); runs=91:95;
rows=repmat(template(),0,1);
for run=runs
    seed=cfg.seed_base+710000000+1000*run;
    rng(seed,'twister');
    [Task,Fog,Thing,DNN_Data]=generate_tier1_env_trace(N,cfg.fog_num_fixed);
    [Fog,meta]=MCA_Apply_Infrastructure_Profile(Fog,'latency_comm_v2');
    state=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,N);
    out=template(); out.Run=run; out.Seed=seed; out.N=N; out.CapacityRef=row.CapacityRef(1);
    out.NormalizedLoad=lambda; out.BandwidthScale=meta.BandwidthScale;
    out.ComputePressure=state.ComputePressure; out.MemoryPressure=state.MemoryPressure;
    out.LinkPressure=state.BandwidthPressure; out.ComputeGain=state.ActionGainFull(1);
    out.MemoryGain=state.ActionGainFull(2); out.BandwidthGain=state.ActionGainFull(3);
    out.IntrinsicInfeasibleFraction=state.IntrinsicInfeasibleFraction;
    out.LinkPressureDominant=out.LinkPressure>= ...
        max(out.ComputePressure,out.MemoryPressure);
    out.BandwidthResponsive=out.BandwidthGain>=0.005;
    out.BandwidthGainDominant=out.BandwidthGain>=0.005 && ...
        out.BandwidthGain>=1.25*max(out.ComputeGain,out.MemoryGain);
    out.NonDegenerate=out.IntrinsicInfeasibleFraction<=0.95;
    out.RunGate=out.BandwidthResponsive && out.BandwidthGainDominant && out.NonDegenerate;
    rows(end+1)=out; %#ok<AGROW>
end
tbl=struct2table(rows);
aggregate_non_degenerate=mean(tbl.IntrinsicInfeasibleFraction)>=0.05 && ...
    mean(tbl.IntrinsicInfeasibleFraction)<=0.95;
tbl.ProfileGate(:)=all(tbl.RunGate) && aggregate_non_degenerate;
writetable(tbl,fullfile(cfg.results_root,'LatencyCommV2_Discriminability.csv'));
assert(all(tbl.ProfileGate),'MCA:LatencyV2Discriminability', ...
    'The frozen latency_comm_v2 profile failed at capacity-normalized load.');
fprintf('LATENCY COMM V2 DISCRIMINABILITY PASS: 5/5 runs, C=%d, N=%d, load=%.2f\n', ...
    row.CapacityRef(1),N,lambda);
disp(tbl);
end

function row=template()
row=struct('Run',0,'Seed',0,'N',0,'CapacityRef',0,'NormalizedLoad',0, ...
    'BandwidthScale',0,'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'LinkPressureDominant',false, ...
    'BandwidthResponsive',false, ...
    'BandwidthGainDominant',false,'NonDegenerate',false,'RunGate',false);
end
