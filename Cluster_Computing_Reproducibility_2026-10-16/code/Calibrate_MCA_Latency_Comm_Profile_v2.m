function Calibrate_MCA_Latency_Comm_Profile_v2()
% Freeze a communication-dominant profile without using controller outcomes.
cfg=MCA_Official_Setup('audit');
runs=71:75; sample_n=150;
scales=[0.000625,0.0005,0.0004,0.00032,0.00025];
root=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'LATENCY_COMM_V2_PROFILE_CALIBRATION');
if ~exist(root,'dir'),mkdir(root);end
rows=repmat(row_template(),0,1);
for run=runs
    seed=cfg.seed_base+700000000+1000*run;
    rng(seed,'twister');
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
        row.LinkPressureDominant=state.BandwidthPressure>=0.85 && ...
            state.BandwidthPressure>=1.25*max(state.ComputePressure,state.MemoryPressure);
        row.BandwidthGainDominant=state.ActionGainFull(3)>=0.005 && ...
            state.ActionGainFull(3)>=1.25*max(state.ActionGainFull(1:2));
        row.NonDegenerate=state.IntrinsicInfeasibleFraction>=0.05 && ...
            state.IntrinsicInfeasibleFraction<=0.95;
        row.RunGate=row.LinkPressureDominant && row.BandwidthGainDominant && row.NonDegenerate;
        rows(end+1)=row; %#ok<AGROW>
    end
end
tbl=struct2table(rows);
writetable(tbl,fullfile(root,'LatencyCommV2_Profile_Probe.csv'));
summary=repmat(summary_template(),0,1);
for scale=scales
    block=tbl(abs(tbl.BandwidthScale-scale)<1e-12,:);
    row=summary_template(); row.BandwidthScale=scale; row.Runs=height(block);
    row.MeanComputePressure=mean(block.ComputePressure);
    row.MeanMemoryPressure=mean(block.MemoryPressure);
    row.MeanLinkPressure=mean(block.LinkPressure);
    row.MeanComputeGain=mean(block.ComputeGain); row.MeanMemoryGain=mean(block.MemoryGain);
    row.MeanBandwidthGain=mean(block.BandwidthGain);
    row.MeanIntrinsicInfeasibleFraction=mean(block.IntrinsicInfeasibleFraction);
    row.PassingRuns=sum(block.RunGate); row.ProfileGate=all(block.RunGate);
    summary(end+1)=row; %#ok<AGROW>
end
summary_tbl=struct2table(summary);
passing=summary_tbl(summary_tbl.ProfileGate,:);
assert(~isempty(passing),'MCA:LatencyCommProfileGate', ...
    'No candidate bandwidth scale passed all profile gates.');
selected=max(passing.BandwidthScale);
summary_tbl.Selected=abs(summary_tbl.BandwidthScale-selected)<1e-12;
writetable(summary_tbl,fullfile(root,'LatencyCommV2_Profile_Summary.csv'));
frozen=struct('Profile',"latency_comm_v2",'BandwidthScale',selected, ...
    'Runs',runs,'Seeds',cfg.seed_base+700000000+1000*runs,'SampleN',sample_n, ...
    'Gate',"all five runs: link pressure and bandwidth gain dominant; non-degenerate");
save(fullfile(root,'LatencyCommV2_Profile_Frozen.mat'),'frozen','summary_tbl','tbl');
fprintf('LATENCY COMM V2 PROFILE GATE PASS: scale=%.8f, runs=%s\n',selected,mat2str(runs));
disp(summary_tbl);
end

function row=row_template()
row=struct('Run',0,'Seed',0,'SampleN',0,'BandwidthScale',0, ...
    'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'LinkPressureDominant',false, ...
    'BandwidthGainDominant',false,'NonDegenerate',false,'RunGate',false);
end

function row=summary_template()
row=struct('BandwidthScale',0,'Runs',0,'MeanComputePressure',0, ...
    'MeanMemoryPressure',0,'MeanLinkPressure',0,'MeanComputeGain',0, ...
    'MeanMemoryGain',0,'MeanBandwidthGain',0, ...
    'MeanIntrinsicInfeasibleFraction',0,'PassingRuns',0,'ProfileGate',false);
end
