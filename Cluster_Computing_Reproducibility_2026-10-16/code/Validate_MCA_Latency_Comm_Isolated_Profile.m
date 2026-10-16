function Validate_MCA_Latency_Comm_Isolated_Profile()
mode='capacityphaselatencyisolatedv1final'; cfg=MCA_Official_Setup(mode);
capacity_file=fullfile(cfg.results_root,'Capacity_Reference_Frozen.csv');
assert(exist(capacity_file,'file')==2,'MCA:IsolatedCapacityMissing','Run capacity calibration first.');
capacity=readtable(capacity_file,'TextType','string');
ref=capacity(capacity.Profile=="latency_comm_isolated_v1",:);
assert(height(ref)==1 && ref.CapacityRef(1)>=1,'MCA:IsolatedCapacity','Invalid capacity reference.');
lambda=0.55; N=round(ref.CapacityRef(1)*lambda); runs=121:125;
rows=repmat(template(),0,1);
for run=runs
    seed=cfg.seed_base+730000000+1000*run; rng(seed,'twister');
    [Task,Fog,Thing,DNN_Data]=generate_tier1_env_trace(N,cfg.fog_num_fixed);
    [Fog,meta]=MCA_Apply_Infrastructure_Profile(Fog,'latency_comm_isolated_v1');
    state=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,N);
    row=template(); row.Run=run; row.Seed=seed; row.N=N; row.CapacityRef=ref.CapacityRef(1);
    row.MemoryScale=meta.MemoryScale; row.BandwidthScale=meta.BandwidthScale;
    row.ComputePressure=state.ComputePressure; row.MemoryPressure=state.MemoryPressure;
    row.LinkPressure=state.BandwidthPressure; row.ComputeGain=state.ActionGainFull(1);
    row.MemoryGain=state.ActionGainFull(2); row.BandwidthGain=state.ActionGainFull(3);
    row.IntrinsicInfeasibleFraction=state.IntrinsicInfeasibleFraction;
    row.LinkPressureIsolated=row.LinkPressure>=1.10*max(row.ComputePressure,row.MemoryPressure);
    row.BandwidthGainDominant=row.BandwidthGain>=0.005 && ...
        row.BandwidthGain>=1.25*max(row.ComputeGain,row.MemoryGain);
    row.RunGate=row.LinkPressureIsolated && row.BandwidthGainDominant && ...
        row.IntrinsicInfeasibleFraction<=0.95;
    rows(end+1)=row; %#ok<AGROW>
end
tbl=struct2table(rows);
aggregate_non_degenerate=mean(tbl.IntrinsicInfeasibleFraction)>=0.05;
tbl.ProfileGate(:)=all(tbl.RunGate) && aggregate_non_degenerate;
writetable(tbl,fullfile(cfg.results_root,'LatencyCommIsolatedV1_Discriminability.csv'));
assert(all(tbl.ProfileGate),'MCA:IsolatedDiscriminability', ...
    'The isolated profile failed held-out resource discriminability.');
fprintf('LATENCY COMM ISOLATED V1 DISCRIMINABILITY PASS: 5/5, C=%d N=%d\n', ...
    ref.CapacityRef(1),N);
disp(tbl);
end

function row=template()
row=struct('Run',0,'Seed',0,'N',0,'CapacityRef',0,'MemoryScale',0, ...
    'BandwidthScale',0,'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'LinkPressureIsolated',false, ...
    'BandwidthGainDominant',false,'RunGate',false);
end
