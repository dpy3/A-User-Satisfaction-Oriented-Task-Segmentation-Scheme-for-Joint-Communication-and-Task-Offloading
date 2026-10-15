function Analyze_MCA_Offline_GNN(mode)
if nargin < 1 || isempty(mode), mode = 'formal'; end
root = fileparts(mfilename('fullpath'));
learned_path = fullfile(root, 'Results', ['OFFLINEGNN_' upper(char(mode)) '_FIXED5'], ...
    'OfflineGNN_Test_RunLevel.csv');
main_path = fullfile(root, 'Results', 'BASELINEFORMAL_FIXED5', 'Static_RunLevel.csv');
assert(exist(learned_path, 'file') == 2 && exist(main_path, 'file') == 2, ...
    'GNN:MissingAnalysisInput', 'OfflineGNN or official baseline input is missing.');
learned = readtable(learned_path, 'TextType', 'string');
main = readtable(main_path, 'TextType', 'string');
test_runs = unique(learned.Run)'; scales = unique(learned.N)';
alm = sortrows(main(main.Algorithm == "ALM" & ismember(main.N, scales) & ...
    ismember(main.Run, test_runs), :), {'N','Run'});
learned = sortrows(learned, {'N','Run'});
assert(isequal(alm.N, learned.N) && isequal(alm.Run, learned.Run) && isequal(alm.Seed, learned.Seed), ...
    'GNN:OfficialPairing', 'OfflineGNN rows do not pair with official ALM rows.');

rows = repmat(row_template(), 0, 1);
for N = scales
    mask = learned.N == N;
    rows(end + 1) = summarize(N, alm.Sat(mask), learned.Sat(mask), ...
        2026072800 + N); %#ok<AGROW>
end
by_scale = struct2table(rows);
by_scale.PHolm = holm_adjust(by_scale.PSignFlip);
result_dir = fileparts(learned_path);
writetable(by_scale, fullfile(result_dir, 'OfflineGNN_ALM_Paired_Analysis.csv'));

run_effect = zeros(numel(test_runs), 1);
for i = 1:numel(test_runs)
    mask = learned.Run == test_runs(i);
    run_effect(i) = mean(alm.Sat(mask) - learned.Sat(mask));
end
[low, high] = bootstrap_ci(run_effect, 2026072899, 20000);
overall = table(numel(test_runs), numel(scales), mean(run_effect), low, high, ...
    paired_dz(run_effect), sum(run_effect > 1e-10), sum(abs(run_effect) <= 1e-10), ...
    sum(run_effect < -1e-10), signflip_pvalue(run_effect), ...
    'VariableNames', {'IndependentRuns','ScalesPerRun','MeanALMMinusOfflineGNN', ...
    'CI95Low','CI95High','PairedCohenDz','Wins','Ties','Losses','PSignFlip'});
writetable(overall, fullfile(result_dir, 'OfflineGNN_ALM_Primary.csv'));
disp(by_scale); disp(overall);
end

function row = row_template()
row = struct('N',0,'Pairs',0,'ALMMean',0,'OfflineGNNMean',0, ...
    'MeanALMMinusOfflineGNN',0,'CI95Low',0,'CI95High',0,'PairedCohenDz',0, ...
    'Wins',0,'Ties',0,'Losses',0,'PSignFlip',0);
end

function row = summarize(N, alm, learned, seed)
d = alm - learned; [low, high] = bootstrap_ci(d, seed, 20000);
row = row_template(); row.N=N; row.Pairs=numel(d); row.ALMMean=mean(alm);
row.OfflineGNNMean=mean(learned); row.MeanALMMinusOfflineGNN=mean(d);
row.CI95Low=low; row.CI95High=high; row.PairedCohenDz=paired_dz(d);
row.Wins=sum(d>1e-10); row.Ties=sum(abs(d)<=1e-10); row.Losses=sum(d< -1e-10);
row.PSignFlip=signflip_pvalue(d);
end

function value = paired_dz(d)
value=0; if std(d)>1e-12, value=mean(d)/std(d); end
end

function [low, high] = bootstrap_ci(d, seed, B)
d=d(:); rng(seed,'twister'); boot=sort(mean(d(randi(numel(d),numel(d),B)),1));
low=boot(max(1,round(.025*B))); high=boot(min(B,round(.975*B)));
end

function p = signflip_pvalue(d)
d=d(:); if all(abs(d)<eps), p=1; return; end
n=numel(d); B=100000; rng(2026072801+n,'twister');
signs=2*(rand(n,B)>.5)-1; observed=abs(mean(d));
p=(sum(abs(mean(d.*signs,1))>=observed-1e-12)+1)/(B+1);
end

function adjusted = holm_adjust(raw)
[sorted,order]=sort(raw); m=numel(raw); temp=zeros(m,1);
for i=1:m, temp(i)=min(1,(m-i+1)*sorted(i)); end
for i=2:m, temp(i)=max(temp(i),temp(i-1)); end
adjusted=zeros(m,1); adjusted(order)=temp;
end
