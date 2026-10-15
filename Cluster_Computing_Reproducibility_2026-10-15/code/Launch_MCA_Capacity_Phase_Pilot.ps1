$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$matlab = 'E:\Application\matlab2025a\bin\matlab.exe'
$results = Join-Path $root 'Results\CAPACITYPHASEPILOT_FIXED5'
New-Item -ItemType Directory -Force -Path $results | Out-Null

$profiles = @('balanced', 'compute_bound', 'memory_bound', 'latency_filtered', 'edge_rich')
$workers = @()
foreach ($profile in $profiles) {
    $stdout = Join-Path $results ("CapacityPhase_{0}_stdout.log" -f $profile)
    $stderr = Join-Path $results ("CapacityPhase_{0}_stderr.log" -f $profile)
    $batch = "cd('$($root.Replace('\','/'))'); Run_MCA_Capacity_Phase_Shard('$profile',56,60);"
    $arguments = "-batch `"$batch`""
    $process = Start-Process -FilePath $matlab -ArgumentList $arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $workers += [pscustomobject]@{
        Profile = $profile
        PID = $process.Id
        StartedAt = (Get-Date).ToString('s')
        Stdout = $stdout
        Stderr = $stderr
    }
}
$workers | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $results 'CapacityPhase_Pilot_Workers.csv')
$workers | Format-Table -AutoSize
