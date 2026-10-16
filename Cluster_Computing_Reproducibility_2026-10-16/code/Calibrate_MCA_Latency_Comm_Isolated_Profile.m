function Calibrate_MCA_Latency_Comm_Isolated_Profile()
% Freeze a communication bottleneck with explicit memory headroom.
cfg=MCA_Official_Setup('audit'); runs=111:115; sample_n=150;
bandwidth_scales=[0.0008,0.001,0.00125,0.0016]; memory_scales=[1.5,2,3];
root=fullfile(fileparts(mfilename('fullpath')),'Results', ...
    'LATENCY_COMM_ISOLATED_V1_PROFILE_CALIBRATION');
if ~exist(root,'dir'),mkdir(root);end
rows=repmat(template(),0,1);
for run=runs
    seed=cfg.seed_base+720000000+1000*run; rng(seed,'twister');
    [Task,base_fog,Thing,DNN_Data]=generate_tier1_env_trace(sample_n,cfg.fog_num_fixed);
    for memory_scale=memory_scales
        for bandwidth_scale=bandwidth_scales
            Fog=base_fog; Fog(:,6)=Fog(:,6)*bandwidth_scale;
            Fog(:,8)=Fog(:,8)*memory_scale;
            state=MCA_MultiResource_State(Task,Fog,Thing,DNN_Data,0,sample_n);
            row=template(); row.Run=run; row.Seed=seed; row.SampleN=sample_n;
            row.MemoryScale=memory_scale; row.BandwidthScale=bandwidth_scale;
            row.ComputePressure=state.ComputePressure; row.MemoryPressure=state.MemoryPressure;
            row.LinkPressure=state.BandwidthPressure; row.ComputeGain=state.ActionGainFull(1);
            row.MemoryGain=state.ActionGainFull(2); row.BandwidthGain=state.ActionGainFull(3);
            row.IntrinsicInfeasibleFraction=state.IntrinsicInfeasibleFraction;
            row.LinkPressureIsolated=row.LinkPressure>=1.10* ...
                max(row.ComputePressure,row.MemoryPressure);
            row.BandwidthGainDominant=row.BandwidthGain>=0.005 && ...
                row.BandwidthGain>=1.25*max(row.ComputeGain,row.MemoryGain);
            row.RunGate=row.LinkPressureIsolated && row.BandwidthGainDominant && ...
                row.IntrinsicInfeasibleFraction<=0.95;
            rows(end+1)=row; %#ok<AGROW>
        end
    end
end
tbl=struct2table(rows);
writetable(tbl,fullfile(root,'LatencyCommIsolatedV1_Profile_Probe.csv'));
summary=repmat(summary_template(),0,1);
for memory_scale=memory_scales
    for bandwidth_scale=bandwidth_scales
        block=tbl(abs(tbl.MemoryScale-memory_scale)<1e-12 & ...
            abs(tbl.BandwidthScale-bandwidth_scale)<1e-12,:);
        row=summary_template(); row.MemoryScale=memory_scale;
        row.BandwidthScale=bandwidth_scale; row.Runs=height(block);
        row.MeanComputePressure=mean(block.ComputePressure);
        row.MeanMemoryPressure=mean(block.MemoryPressure);
        row.MeanLinkPressure=mean(block.LinkPressure);
        row.MeanBandwidthGain=mean(block.BandwidthGain);
        row.MinBandwidthGain=min(block.BandwidthGain);
        row.MeanIntrinsicInfeasibleFraction=mean(block.IntrinsicInfeasibleFraction);
        row.PassingRuns=sum(block.RunGate);
        row.ProfileGate=all(block.RunGate) && ...
            row.MeanIntrinsicInfeasibleFraction>=0.05;
        summary(end+1)=row; %#ok<AGROW>
    end
end
summary_tbl=struct2table(summary); passing=summary_tbl(summary_tbl.ProfileGate,:);
assert(~isempty(passing),'MCA:LatencyIsolatedProfileGate','No isolated profile passed.');
max_bw=max(passing.BandwidthScale); finalists=passing(passing.BandwidthScale==max_bw,:);
selected_memory=min(finalists.MemoryScale);
selected=summary_tbl.BandwidthScale==max_bw & summary_tbl.MemoryScale==selected_memory;
summary_tbl.Selected=selected;
writetable(summary_tbl,fullfile(root,'LatencyCommIsolatedV1_Profile_Summary.csv'));
frozen=struct('Profile',"latency_comm_isolated_v1",'BandwidthScale',max_bw, ...
    'MemoryScale',selected_memory,'Runs',runs, ...
    'Seeds',cfg.seed_base+720000000+1000*runs,'SampleN',sample_n, ...
    'SelectionRule',"maximum bandwidth then minimum memory headroom passing 5/5 gates");
save(fullfile(root,'LatencyCommIsolatedV1_Profile_Frozen.mat'), ...
    'frozen','summary_tbl','tbl');
fprintf('LATENCY COMM ISOLATED V1 PROFILE PASS: memory=%.2f bandwidth=%.7f\n', ...
    selected_memory,max_bw);
disp(summary_tbl(summary_tbl.Selected,:));
end

function row=template()
row=struct('Run',0,'Seed',0,'SampleN',0,'MemoryScale',0,'BandwidthScale',0, ...
    'ComputePressure',0,'MemoryPressure',0,'LinkPressure',0, ...
    'ComputeGain',0,'MemoryGain',0,'BandwidthGain',0, ...
    'IntrinsicInfeasibleFraction',0,'LinkPressureIsolated',false, ...
    'BandwidthGainDominant',false,'RunGate',false);
end

function row=summary_template()
row=struct('MemoryScale',0,'BandwidthScale',0,'Runs',0, ...
    'MeanComputePressure',0,'MeanMemoryPressure',0,'MeanLinkPressure',0, ...
    'MeanBandwidthGain',0,'MinBandwidthGain',0, ...
    'MeanIntrinsicInfeasibleFraction',0,'PassingRuns',0,'ProfileGate',false);
end
