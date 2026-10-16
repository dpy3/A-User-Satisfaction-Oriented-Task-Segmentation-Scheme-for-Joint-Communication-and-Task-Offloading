function Validate_MCA_Latency_Comm_Isolated_v3()
cfg=MCA_Official_Setup('capacityphaselatencyisolatedv3final');
capacity=readtable(fullfile(cfg.results_root,'Capacity_Reference_Frozen.csv'),'TextType','string');
ref=capacity(capacity.Profile=="latency_comm_isolated_v3",:);
assert(height(ref)==1 && ref.MinCapacityEstimate(1)>=1,'MCA:IsolatedV3Capacity', ...
    'All five capacity runs must have positive capacity.');
lambda=0.55; N=round(ref.CapacityRef(1)*lambda); runs=166:170; slots=100;
rows=repmat(template(),0,1);
for run=runs
    for slot=1:slots
        seed=cfg.seed_base+770000000+100000*run+slot; rng(seed,'twister');
        [Task,Fog,Thing,DNN_Data]=generate_tier1_env_trace(N,cfg.fog_num_fixed);
        [Fog,meta]=MCA_Apply_Infrastructure_Profile(Fog,'latency_comm_isolated_v3');
        s=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,N);
        row=template(); row.Run=run; row.Slot=slot; row.Seed=seed; row.N=N;
        row.CapacityRef=ref.CapacityRef(1); row.ComputeScale=meta.ComputeScale;
        row.MemoryScale=meta.MemoryScale; row.BandwidthScale=meta.BandwidthScale;
        row.ComputePressure=s.ComputePressure; row.MemoryPressure=s.MemoryPressure;
        row.LinkPressure=s.BandwidthPressure; row.ComputeGain=s.ActionGainFull(1);
        row.MemoryGain=s.ActionGainFull(2); row.BandwidthGain=s.ActionGainFull(3);
        row.IntrinsicInfeasibleFraction=s.IntrinsicInfeasibleFraction;
        row.BandwidthResponsive=row.BandwidthGain>=0.005 && ...
            row.BandwidthGain>=1.25*max(row.ComputeGain,row.MemoryGain);
        rows(end+1)=row; %#ok<AGROW>
    end
end
tbl=struct2table(rows);
summary=repmat(summary_template(),0,1);
for run=runs
    block=tbl(tbl.Run==run,:); row=summary_template(); row.Run=run; row.Slots=height(block);
    row.MeanComputePressure=mean(block.ComputePressure);
    row.MeanMemoryPressure=mean(block.MemoryPressure); row.MeanLinkPressure=mean(block.LinkPressure);
    row.MeanComputeGain=mean(block.ComputeGain); row.MeanMemoryGain=mean(block.MemoryGain);
    row.MeanBandwidthGain=mean(block.BandwidthGain);
    row.ResponsiveFraction=mean(block.BandwidthResponsive);
    row.MeanIntrinsicInfeasibleFraction=mean(block.IntrinsicInfeasibleFraction);
    row.RunGate=row.MeanBandwidthGain>=0.005 && ...
        row.MeanBandwidthGain>=1.25*max(row.MeanComputeGain,row.MeanMemoryGain) && ...
        row.ResponsiveFraction>=0.60 && row.MeanIntrinsicInfeasibleFraction>=0.05 && ...
        row.MeanIntrinsicInfeasibleFraction<=0.95;
    summary(end+1)=row; %#ok<AGROW>
end
summary_tbl=struct2table(summary); summary_tbl.ProfileGate(:)=all(summary_tbl.RunGate);
writetable(tbl,fullfile(cfg.results_root,'LatencyCommIsolatedV3_Discriminability_Slot.csv'));
writetable(summary_tbl,fullfile(cfg.results_root,'LatencyCommIsolatedV3_Discriminability_Run.csv'));
assert(all(summary_tbl.ProfileGate),'MCA:IsolatedV3Discriminability', ...
    'The 5-run x 100-slot discriminability gate failed.');
fprintf('LATENCY COMM ISOLATED V3 PASS: C=%d N=%d, 5x100 slot gate.\n', ...
    ref.CapacityRef(1),N);
disp(summary_tbl);
end

function row=template()
row=struct('Run',0,'Slot',0,'Seed',0,'N',0,'CapacityRef',0, ...
    'ComputeScale',0,'MemoryScale',0,'BandwidthScale',0, ...
    'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'BandwidthResponsive',false);
end

function row=summary_template()
row=struct('Run',0,'Slots',0,'MeanComputePressure',0,'MeanMemoryPressure',0, ...
    'MeanLinkPressure',0,'MeanComputeGain',0,'MeanMemoryGain',0, ...
    'MeanBandwidthGain',0,'ResponsiveFraction',0, ...
    'MeanIntrinsicInfeasibleFraction',0,'RunGate',false);
end
