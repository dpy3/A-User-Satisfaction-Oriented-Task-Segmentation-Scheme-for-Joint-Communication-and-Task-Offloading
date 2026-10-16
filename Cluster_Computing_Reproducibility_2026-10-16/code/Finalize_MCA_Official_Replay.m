function Finalize_MCA_Official_Replay(mode)
if nargin < 1 || isempty(mode), mode = 'selectorformal'; end
Merge_MCA_Official_Replay(mode, true);
Analyze_MCA_Official_Replay(mode);
fprintf('FINAL REPLAY EVIDENCE PASS: merged validation and paired analysis completed.\n');
end
