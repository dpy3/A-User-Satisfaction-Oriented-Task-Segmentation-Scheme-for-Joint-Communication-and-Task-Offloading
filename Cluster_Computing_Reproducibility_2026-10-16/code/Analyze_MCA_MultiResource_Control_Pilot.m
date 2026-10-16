function Analyze_MCA_MultiResource_Control_Pilot(mode)
if nargin<1 || isempty(mode),mode='smoke';end
root=fileparts(mfilename('fullpath')); dirpath=fullfile(root,'Results',['MULTIRESOURCE_' upper(char(mode))]);
tbl=readtable(fullfile(dirpath,'MultiResource_Control_RunLevel.csv'),'TextType','string');
profiles=unique(tbl.Profile,'stable');
if ismember(lower(char(mode)),{'smoke6','pilot4'})
    ly_name="LyapunovMRv3"; mp_name="MPCMRV2"; fx_name="FixedMatchedV2";
elseif strcmpi(mode,'pilot3') || startsWith(lower(char(mode)),'smoke3') || ...
        ismember(lower(char(mode)),{'smoke4','smoke5'})
    ly_name="LyapunovMRv2"; mp_name="MPCMRV2"; fx_name="FixedMatchedV2";
else
    ly_name="LyapunovMR"; mp_name="MPCMR"; fx_name="FixedMatched";
end
summary=groupsummary(tbl,{'Profile','Policy'},{'mean','std'}, ...
    {'MeanSat','QueueDrops','BacklogAUC','InterventionCostUnits','RuntimeSec'});
writetable(summary,fullfile(dirpath,'MultiResource_Control_Summary.csv'));
rows=struct('Profile',{},'LyapunovMinusNoActionSat',{},'LyapunovMinusMPCSat',{}, ...
    'LyapunovMinusFixedSat',{},'LyapunovCost',{},'MPCost',{}, ...
    'FixedCost',{},'CostWithinFixed',{},'PilotSignal',{});
for i=1:numel(profiles)
    profile=profiles(i); block=tbl(tbl.Profile==profile,:);
    ly=sortrows(block(block.Policy==ly_name,:),'Run');
    no=sortrows(block(block.Policy=="NoAction",:),'Run');
    mp=sortrows(block(block.Policy==mp_name,:),'Run');
    fx=sortrows(block(block.Policy==fx_name,:),'Run');
    cost_within_fixed=mean(ly.InterventionCostUnits)<=mean(fx.InterventionCostUnits)+1e-9;
    rows(end+1)=struct('Profile',profile, ...
        'LyapunovMinusNoActionSat',mean(ly.MeanSat-no.MeanSat), ...
        'LyapunovMinusMPCSat',mean(ly.MeanSat-mp.MeanSat), ...
        'LyapunovMinusFixedSat',mean(ly.MeanSat-fx.MeanSat), ...
        'LyapunovCost',mean(ly.InterventionCostUnits), ...
        'MPCost',mean(mp.InterventionCostUnits), ...
        'FixedCost',mean(fx.InterventionCostUnits), ...
        'CostWithinFixed',cost_within_fixed, ...
        'PilotSignal',mean(ly.MeanSat)>=mean(no.MeanSat) && ...
        mean(ly.MeanSat)>=mean(fx.MeanSat) && cost_within_fixed); %#ok<AGROW>
end
contrasts=struct2table(rows);
pilot_gate=all(contrasts.PilotSignal);
contrasts.PilotGate(:)=pilot_gate;
writetable(contrasts,fullfile(dirpath,'MultiResource_Control_Contrasts.csv'));
disp(summary); disp(contrasts);
fprintf('PAPER 3 PILOT SIGNALS: %d/%d profiles. Smoke/pilot is not confirmatory evidence.\n', ...
    sum(contrasts.PilotSignal),numel(profiles));
if startsWith(lower(char(mode)),'pilot')
    if pilot_gate
        fprintf('PAPER 3 PILOT GATE PASS: all profiles meet service and matched-cost gates.\n');
    else
        fprintf('PAPER 3 PILOT GATE FAIL: do not start formal experiments.\n');
    end
end
end
