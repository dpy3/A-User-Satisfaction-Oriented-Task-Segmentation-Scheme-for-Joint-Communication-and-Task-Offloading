param([int]$PollSeconds = 300)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$matlab = 'E:\Application\matlab2025a\bin\matlab.exe'
$results = Join-Path $root 'Results\CAPACITYCODESIGNPILOT_FIXED5'
$log = Join-Path $results 'Continue_MCA_Capacity_CoDesign_Pilot.log'
$profiles = @('balanced', 'compute_bound', 'memory_bound', 'latency_filtered', 'edge_rich')
$expected = @($profiles | ForEach-Object { "CapacityCoDesign_SlotLevel_${_}_L3_R66to70.csv" })

function Write-Log([string]$message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Tee-Object -FilePath $log -Append
}

Write-Log "Co-design pilot monitor started; polling every $PollSeconds seconds."
while ($true) {
    $stderr = @(Get-ChildItem $results -Filter 'CapacityCoDesign_*_stderr.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 })
    if ($stderr.Count -gt 0) { Write-Log "ERROR: non-empty stderr logs: $($stderr.Name -join ', ')"; exit 2 }
    $missing = @($expected | Where-Object { -not (Test-Path (Join-Path $results $_)) })
    if ($missing.Count -eq 0) {
        Write-Log 'All co-design shards detected; starting merge and validation.'
        & $matlab -batch "cd('$($root.Replace('\','/'))'); Merge_MCA_Capacity_CoDesign('capacitycodesignpilot',true);" *>> $log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        python (Join-Path $root 'Analyze_MCA_Capacity_CoDesign.py') capacitycodesignpilot *>> $log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Log 'Capacity co-design pilot finalize complete.'
        exit 0
    }
    Write-Log "Waiting for $($missing.Count) co-design shards: $($missing -join ', ')"
    Start-Sleep -Seconds $PollSeconds
}
