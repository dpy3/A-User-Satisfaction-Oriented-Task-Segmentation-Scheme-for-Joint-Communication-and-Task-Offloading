param([int]$PollSeconds = 120)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$matlab = 'E:\Application\matlab2025a\bin\matlab.exe'
$results = Join-Path $root 'Results\CAPACITYPHASEEXTENSION_FIXED5'
$log = Join-Path $results 'Continue_MCA_Capacity_Phase_Extension.log'
$profiles = @('compute_bound', 'latency_filtered')
$expected = @($profiles | ForEach-Object { "CapacityPhase_SlotLevel_${_}_L5_R61to65.csv" })

function Write-Log([string]$message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message" | Tee-Object -FilePath $log -Append
}

Write-Log "Extension monitor started; polling every $PollSeconds seconds."
while ($true) {
    $stderr = @(Get-ChildItem $results -Filter 'CapacityPhase_*_stderr.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 })
    if ($stderr.Count -gt 0) { Write-Log "ERROR: non-empty stderr logs: $($stderr.Name -join ', ')"; exit 2 }
    $missing = @($expected | Where-Object { -not (Test-Path (Join-Path $results $_)) })
    if ($missing.Count -eq 0) {
        Write-Log 'All extension shards detected; starting merge and validation.'
        & $matlab -batch "cd('$($root.Replace('\','/'))'); Merge_MCA_Capacity_Phase('capacityphaseextension',true);" *>> $log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        python (Join-Path $root 'Analyze_MCA_Capacity_Phase.py') capacityphaseextension *>> $log
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Log 'Capacity-phase extension finalize complete.'
        exit 0
    }
    Write-Log "Waiting for $($missing.Count) extension shards: $($missing -join ', ')"
    Start-Sleep -Seconds $PollSeconds
}
