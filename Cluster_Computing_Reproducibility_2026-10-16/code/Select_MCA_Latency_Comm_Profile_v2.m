function Select_MCA_Latency_Comm_Profile_v2()
% Jointly freeze the mildest capacity-viable, bandwidth-responsive profile.
cfg=MCA_Official_Setup('audit'); runs=71:75; sample_n=150;
scales=[0.0008,0.001,0.00125,0.0016,0.002,0.0025,0.0032,0.004,0.005];
root=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'LATENCY_COMM_V2_PROFILE_CALIBRATION');
capacity_file=fullfile(root,'LatencyCommV2_Capacity_Summary.csv');
assert(exist(capacity_file,'file')==2,'MCA:LatencyV2CapacityProbeMissing', ...
    'Run Probe_MCA_Latency_Comm_v2_Capacity first.');
capacity=readtable(capacity_file,'TextType','string');
rows=repmat(row_template(),0,1);
for run=runs
    seed=cfg.seed_base+700000000+1000*run; rng(seed,'twister');
    [Task,base_fog,Thing,DNN_Data]=generate_tier1_env_trace(sample_n,cfg.fog_num_fixed);
    for scale=scales
        Fog=base_fog; Fog(:,6)=Fog(:,6)*scale;
        state=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,sample_n);
        row=row_template(); row.Run=run; row.Seed=seed; row.SampleN=sample_n;
        row.BandwidthScale=scale; row.ComputePressure=state.ComputePressure;
        row.MemoryPressure=state.MemoryPressure; row.LinkPressure=state.BandwidthPressure;
        row.ComputeGain=state.ActionGainFull(1); row.MemoryGain=state.ActionGainFull(2);
        row.BandwidthGain=state.ActionGainFull(3);
        row.IntrinsicInfeasibleFraction=state.IntrinsicInfeasibleFraction;
        row.BandwidthResponsive=row.BandwidthGain>=0.005;
        row.BandwidthGainDominant=row.BandwidthGain>= ...
            1.25*max(row.ComputeGain,row.MemoryGain);
        row.NonDegenerate=row.IntrinsicInfeasibleFraction<=0.95;
        row.RunGate=row.BandwidthResponsive && row.BandwidthGainDominant && row.NonDegenerate;
        rows(end+1)=row; %#ok<AGROW>
    end
end
tbl=struct2table(rows);
writetable(tbl,fullfile(root,'LatencyCommV2_Joint_Profile_Probe.csv'));
summary=repmat(summary_template(),0,1);
for scale=scales
    block=tbl(abs(tbl.BandwidthScale-scale)<1e-12,:);
    cap=capacity(abs(capacity.BandwidthScale-scale)<1e-12,:);
    assert(height(cap)==1,'MCA:LatencyV2CapacityScale','Missing capacity row for %.7f.',scale);
    row=summary_template(); row.BandwidthScale=scale; row.ProfileRuns=height(block);
    row.MeanLinkPressure=mean(block.LinkPressure);
    row.MeanBandwidthGain=mean(block.BandwidthGain);
    row.MinBandwidthGain=min(block.BandwidthGain);
    row.MeanIntrinsicInfeasibleFraction=mean(block.IntrinsicInfeasibleFraction);
    row.PassingProfileRuns=sum(block.RunGate);
    row.CapacityRef=round(cap.MedianCapacity(1));
    row.CapacityGate=logical(cap.CapacityGate(1));
    aggregate_non_degenerate=row.MeanIntrinsicInfeasibleFraction>=0.05 && ...
        row.MeanIntrinsicInfeasibleFraction<=0.95;
    row.JointGate=all(block.RunGate) && aggregate_non_degenerate && ...
        row.CapacityGate && row.CapacityRef>=1;
    summary(end+1)=row; %#ok<AGROW>
end
summary_tbl=struct2table(summary); passing=summary_tbl(summary_tbl.JointGate,:);
assert(~isempty(passing),'MCA:LatencyV2JointGate','No joint profile candidate passed.');
selected=max(passing.BandwidthScale);
summary_tbl.Selected=abs(summary_tbl.BandwidthScale-selected)<1e-12;
writetable(summary_tbl,fullfile(root,'LatencyCommV2_Joint_Profile_Summary.csv'));
selected_row=summary_tbl(summary_tbl.Selected,:);
frozen=struct('Profile',"latency_comm_v2",'BandwidthScale',selected, ...
    'CapacityRef',selected_row.CapacityRef,'ProfileRuns',runs, ...
    'ProfileSeeds',cfg.seed_base+700000000+1000*runs,'CapacityRuns',76:80, ...
    'SelectionRule',"maximum bandwidth scale passing all profile and capacity gates");
save(fullfile(root,'LatencyCommV2_Joint_Profile_Frozen.mat'), ...
    'frozen','summary_tbl','tbl','capacity');
fprintf('LATENCY COMM V2 JOINT GATE PASS: scale=%.7f C=%d\n', ...
    selected,selected_row.CapacityRef);
disp(summary_tbl);
end

function row=row_template()
row=struct('Run',0,'Seed',0,'SampleN',0,'BandwidthScale',0, ...
    'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'BandwidthResponsive',false, ...
    'BandwidthGainDominant',false,'NonDegenerate',false,'RunGate',false);
end

function row=summary_template()
row=struct('BandwidthScale',0,'ProfileRuns',0,'MeanLinkPressure',0, ...
    'MeanBandwidthGain',0,'MinBandwidthGain',0, ...
    'MeanIntrinsicInfeasibleFraction',0,'PassingProfileRuns',0, ...
    'CapacityRef',0,'CapacityGate',false,'JointGate',false);
end
