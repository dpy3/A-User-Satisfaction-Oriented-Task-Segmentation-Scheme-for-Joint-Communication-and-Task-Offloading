$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$matlab = 'E:\Application\matlab2025a\bin\matlab.exe'
$results = Join-Path $root 'Results\CAPACITYPHASEEXTENSION_FIXED5'
$reference = Join-Path $root 'Results\CAPACITYPHASEPILOT_FIXED5'
New-Item -ItemType Directory -Force -Path $results | Out-Null

foreach ($name in 'Capacity_Reference_Frozen.csv','Capacity_Calibration_LP.csv','Capacity_Calibration.mat') {
    Copy-Item -LiteralPath (Join-Path $reference $name) -Destination (Join-Path $results $name) -Force
}

$profiles = @('compute_bound', 'latency_filtered')
$workers = @()
foreach ($profile in $profiles) {
    $stdout = Join-Path $results ("CapacityPhase_{0}_stdout.log" -f $profile)
    $stderr = Join-Path $results ("CapacityPhase_{0}_stderr.log" -f $profile)
    $batch = "cd('$($root.Replace('\','/'))'); Run_MCA_Capacity_Phase_Shard('$profile',61,65,'capacityphaseextension');"
    $process = Start-Process -FilePath $matlab -ArgumentList "-batch `"$batch`"" `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $workers += [pscustomobject]@{Profile=$profile; PID=$process.Id; StartedAt=(Get-Date).ToString('s'); Stdout=$stdout; Stderr=$stderr}
}
$workers | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $results 'CapacityPhase_Extension_Workers.csv')
$workers | Format-Table -AutoSize
