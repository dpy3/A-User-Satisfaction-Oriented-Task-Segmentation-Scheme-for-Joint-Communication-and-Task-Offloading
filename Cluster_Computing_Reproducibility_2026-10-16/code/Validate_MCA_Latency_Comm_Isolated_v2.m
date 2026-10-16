function Validate_MCA_Latency_Comm_Isolated_v2()
cfg=MCA_Official_Setup('capacityphaselatencyisolatedv2final');
capacity=readtable(fullfile(cfg.results_root,'Capacity_Reference_Frozen.csv'),'TextType','string');
ref=capacity(capacity.Profile=="latency_comm_isolated_v2",:);
assert(height(ref)==1 && ref.MinCapacityEstimate(1)>=1,'MCA:IsolatedV2Capacity', ...
    'All capacity calibration runs must have positive capacity.');
lambda=0.55; N=round(ref.CapacityRef(1)*lambda); runs=151:155;
rows=repmat(template(),0,1);
for run=runs
    seed=cfg.seed_base+760000000+1000*run; rng(seed,'twister');
    [Task,Fog,Thing,DNN_Data]=generate_tier1_env_trace(N,cfg.fog_num_fixed);
    [Fog,meta]=MCA_Apply_Infrastructure_Profile(Fog,'latency_comm_isolated_v2');
    s=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,N);
    row=template(); row.Run=run; row.Seed=seed; row.N=N; row.CapacityRef=ref.CapacityRef(1);
    row.ComputeScale=meta.ComputeScale; row.MemoryScale=meta.MemoryScale;
    row.BandwidthScale=meta.BandwidthScale; row.ComputePressure=s.ComputePressure;
    row.MemoryPressure=s.MemoryPressure; row.LinkPressure=s.BandwidthPressure;
    row.ComputeGain=s.ActionGainFull(1); row.MemoryGain=s.ActionGainFull(2);
    row.BandwidthGain=s.ActionGainFull(3);
    row.IntrinsicInfeasibleFraction=s.IntrinsicInfeasibleFraction;
    row.LinkPressureIsolated=row.LinkPressure>=1.10*max(row.ComputePressure,row.MemoryPressure);
    row.BandwidthGainDominant=row.BandwidthGain>=0.005 && ...
        row.BandwidthGain>=1.25*max(row.ComputeGain,row.MemoryGain);
    row.RunGate=row.LinkPressureIsolated && row.BandwidthGainDominant && ...
        row.IntrinsicInfeasibleFraction<=0.95;
    rows(end+1)=row; %#ok<AGROW>
end
tbl=struct2table(rows); aggregate=mean(tbl.IntrinsicInfeasibleFraction)>=0.05;
tbl.ProfileGate(:)=all(tbl.RunGate) && aggregate;
writetable(tbl,fullfile(cfg.results_root,'LatencyCommIsolatedV2_Discriminability.csv'));
assert(all(tbl.ProfileGate),'MCA:IsolatedV2Discriminability', ...
    'Held-out resource discriminability failed.');
fprintf('LATENCY COMM ISOLATED V2 PASS: C=%d N=%d, held-out=5/5\n',ref.CapacityRef(1),N);
disp(tbl);
end

function row=template()
row=struct('Run',0,'Seed',0,'N',0,'CapacityRef',0,'ComputeScale',0, ...
    'MemoryScale',0,'BandwidthScale',0,'ComputePressure',0,'MemoryPressure',0, ...
    'LinkPressure',0,'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'LinkPressureIsolated',false, ...
    'BandwidthGainDominant',false,'RunGate',false);
end
