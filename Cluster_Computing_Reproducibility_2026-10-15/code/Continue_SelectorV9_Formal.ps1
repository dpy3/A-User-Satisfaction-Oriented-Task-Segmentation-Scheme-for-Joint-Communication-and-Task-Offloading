param(
    [int]$PollSeconds = 300
)

$ErrorActionPreference = "Stop"

$Root = "E:\postgraduate\first year\移动边缘计算\01_Submission_Manuscript\Code\MCA_Official_2026"
$Matlab = "E:\Application\matlab2025a\bin\matlab.exe"
$Mode = "selectorv9formal"
$Results = Join-Path $Root "Results\SELECTORV9FORMAL_FIXED5"
$Analysis = Join-Path $Results "SelectorV9_Analysis"
$Log = Join-Path $Results "Continue_SelectorV9_Formal.log"
$Expected = @(
    "Replay_SlotLevel_N240_R11to20.csv",
    "Replay_SlotLevel_N240_R21to30.csv",
    "Replay_SlotLevel_N270_R11to13.csv",
    "Replay_SlotLevel_N270_R14to16.csv",
    "Replay_SlotLevel_N270_R17to20.csv",
    "Replay_SlotLevel_N270_R21to30.csv",
    "Replay_SlotLevel_N300_R11to20.csv",
    "Replay_SlotLevel_N300_R21to28.csv",
    "Replay_SlotLevel_N300_R29to29.csv",
    "Replay_SlotLevel_N300_R30to30.csv"
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
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: MATLAB finalize failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }

        Write-Log "Finalize complete. Starting Python selector-v9 formal analysis."
        python (Join-Path $Root "Analyze_SelectorV9_Calibration.py") $Mode *>> $Log
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERROR: Python analysis failed with exit code $LASTEXITCODE."
            exit $LASTEXITCODE
        }

        if (Test-Path (Join-Path $Analysis "SELECTOR_V9_ANALYSIS_REPORT.md")) {
            Write-Log "Selector-v9 formal analysis complete."
            exit 0
        }

        Write-Log "ERROR: analysis report not found after Python completed."
        exit 3
    }

    Write-Log "Waiting for $($missing.Count) shard CSVs: $($missing -join ', ')"
    Start-Sleep -Seconds $PollSeconds
}
