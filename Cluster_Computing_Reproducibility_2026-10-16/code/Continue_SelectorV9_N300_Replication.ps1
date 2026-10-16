param(
    [int]$PollSeconds = 300
)

$ErrorActionPreference = "Stop"

$Root = "E:\postgraduate\first year\移动边缘计算\01_Submission_Manuscript\Code\MCA_Official_2026"
$Matlab = "E:\Application\matlab2025a\bin\matlab.exe"
$Mode = "selectorv9n300replication"
$Results = Join-Path $Root "Results\SELECTORV9N300REPLICATION_FIXED5"
$Log = Join-Path $Results "Continue_SelectorV9_N300_Replication.log"
$Expected = @(
    "Replay_SlotLevel_N300_R31to33.csv",
    "Replay_SlotLevel_N300_R34to36.csv",
    "Replay_SlotLevel_N300_R37to39.csv",
    "Replay_SlotLevel_N300_R40to42.csv",
    "Replay_SlotLevel_N300_R43to45.csv",
    "Replay_SlotLevel_N300_R46to48.csv",
    "Replay_SlotLevel_N300_R49to50.csv"
)

function Write-Log([string]$Message) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp $Message" | Tee-Object -FilePath $Log -Append
}

Write-Log "Monitor started for $Mode; polling every $PollSeconds seconds."
while ($true) {
    $missing = @($Expected | Where-Object { -not (Test-Path (Join-Path $Results $_)) })
    $stderr = @(Get-ChildItem $Results -Filter "Replay_N*_R*to*_stderr.log" -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 })
    if ($stderr.Count -gt 0) {
        Write-Log "ERROR: non-empty stderr logs detected: $($stderr.Name -join ', ')"
        exit 2
    }
    if ($missing.Count -eq 0) {
        Write-Log "All shard CSVs detected. Starting MATLAB finalize."
        & $Matlab -batch "cd('$Root'); Finalize_MCA_Official_Replay('$Mode');" *>> $Log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Log "Finalize complete. Starting Python analysis."
        python (Join-Path $Root "Analyze_SelectorV9_Calibration.py") $Mode *>> $Log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Log "Independent N=300 replication analysis complete."
        exit 0
    }
    Write-Log "Waiting for $($missing.Count) shard CSVs: $($missing -join ', ')"
    Start-Sleep -Seconds $PollSeconds
}
