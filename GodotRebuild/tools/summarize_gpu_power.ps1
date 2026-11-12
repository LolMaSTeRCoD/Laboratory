<#
.SYNOPSIS
Correlates existing, device-wide AMD ADL telemetry with measured game phases.
.DESCRIPTION
Reads completed JSON reports only. Does not start a game, query the GPU,
change settings or combine warmups/loading/captures with measured phases.
.EXAMPLE
 .\tools\summarize_gpu_power.ps1 -ProfileDirectory .\Builds\GraphicsProfiles\final-power-20261105-022841 -TelemetryJson .\Builds\PowerValidation\amd-load.json
#>
[CmdletBinding()]
param(
    [string]$ProfileDirectory = '',
    [string]$TelemetryJson = (Join-Path $PSScriptRoot '..\Builds\PowerValidation\amd-load.json'),
    [string]$OutputJson = ''
)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$phaseNames = @('far','near','biome_jungle_stress','biome_winter_stress')
$metricNames = @('asic_power_w','gfx_clock_mhz','memory_clock_mhz','gfx_activity_percent','memory_activity_percent','edge_temperature_c','hotspot_temperature_c','fan_rpm','gfx_voltage_mv','board_power_w')

function Numeric-Summary($Values) {
    # Null means unavailable. Zero is valid, including a clock-gated GPU.
    $numbers = @($Values | ForEach-Object {
        if ($null -eq $_ -or ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_))) { return }
        $number = 0.0
        if ([double]::TryParse([string]$_,[Globalization.NumberStyles]::Float,$culture,[ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { $number }
    } | Sort-Object)
    if ($numbers.Count -eq 0) {
        return [ordered]@{n_valid=0;mean=$null;p50=$null;p95=$null;max=$null}
    }
    return [ordered]@{
        n_valid=$numbers.Count
        mean=($numbers | Measure-Object -Average).Average
        p50=$numbers[[Math]::Max(0,[Math]::Ceiling($numbers.Count*0.50)-1)]
        p95=$numbers[[Math]::Max(0,[Math]::Ceiling($numbers.Count*0.95)-1)]
        max=$numbers[-1]
    }
}

if (-not $ProfileDirectory) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\Builds\GraphicsProfiles') -Directory |
        Where-Object { $_.Name -like 'final-power-*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'summary.json')) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $candidate) { throw 'No completed final-power profile found; pass -ProfileDirectory explicitly.' }
    $ProfileDirectory = $candidate.FullName
}
$profilePath = (Resolve-Path -LiteralPath $ProfileDirectory).Path
$telemetryPath = (Resolve-Path -LiteralPath $TelemetryJson).Path
$summaryPath = Join-Path $profilePath 'summary.json'
if (-not (Test-Path -LiteralPath $summaryPath)) { throw 'Profile summary.json is not present. Wait for the native profile to finish.' }
$profile = [IO.File]::ReadAllText($summaryPath) | ConvertFrom-Json
$telemetry = [IO.File]::ReadAllText($telemetryPath) | ConvertFrom-Json
if (@($telemetry.errors).Count -gt 0) { throw ('ADL telemetry contains errors: '+($telemetry.errors -join '; ')) }
$runs = @($profile.runs)
if ($runs.Count -eq 0) { throw 'Expected a complete profile summary with runs[].phase_events.' }
$warnings = [Collections.Generic.List[string]]::new()
$timedSamples = [Collections.Generic.List[object]]::new()
foreach ($sample in @($telemetry.samples)) {
    if ($null -eq $sample) { continue }
    $stamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$sample.timestamp_utc,$culture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$stamp)) {
        $warnings.Add('Ignored an ADL sample with an invalid UTC timestamp.'); continue
    }
    $timedSamples.Add([pscustomobject]@{
        unix_time=$stamp.ToUnixTimeMilliseconds()/1000.0
        adapter_index=$sample.adapter_index
        data=$sample
    })
}
if ($timedSamples.Count -eq 0) { throw 'Telemetry has no timestamped samples.' }

$outputRuns = @()
foreach ($run in $runs) {
    $mode = [string]$run.mode_requested
    $events = @($run.phase_events | Sort-Object {[double]$_.unix_time})
    if ($events.Count -lt 2 -and $null -ne $run.benchmark) { $events = @($run.benchmark.phase_events | Sort-Object {[double]$_.unix_time}) }
    if ($events.Count -lt 2) { throw ('Missing phase boundaries for mode '+$mode) }
    $phaseResults = [ordered]@{}
    foreach ($phase in $phaseNames) {
        $intervals = @()
        for ($eventIndex=0; $eventIndex -lt $events.Count; $eventIndex++) {
            if ([string]$events[$eventIndex].phase -ne $phase) { continue }
            if ($eventIndex+1 -ge $events.Count) {
                $warnings.Add($mode+'/'+$phase+': excluded an open interval without an end event.'); continue
            }
            $start = [double]$events[$eventIndex].unix_time
            $end = [double]$events[$eventIndex+1].unix_time
            if ($end -le $start) { $warnings.Add($mode+'/'+$phase+': ignored a nonpositive measurement interval.'); continue }
            $intervals += [pscustomobject][ordered]@{
                start_unix=$start;end_unix_exclusive=$end;duration_seconds=$end-$start
                start_utc=[DateTimeOffset]::FromUnixTimeMilliseconds([long][Math]::Round($start*1000.0)).UtcDateTime.ToString('o')
                end_utc_exclusive=[DateTimeOffset]::FromUnixTimeMilliseconds([long][Math]::Round($end*1000.0)).UtcDateTime.ToString('o')
            }
        }
        if ($intervals.Count -eq 0) { $warnings.Add($mode+'/'+$phase+': no completed measured phase found.') }
        $matched = @($timedSamples | Where-Object {
            $unix = $_.unix_time
            $inside = $false
            foreach ($interval in $intervals) {
                if ($unix -ge $interval.start_unix -and $unix -lt $interval.end_unix_exclusive) { $inside=$true;break }
            }
            $inside
        })
        $adapters = @()
        foreach ($adapterGroup in @($matched | Group-Object adapter_index)) {
            $stats = [ordered]@{}
            foreach ($metric in $metricNames) {
                $values = @($adapterGroup.Group | ForEach-Object { $_.data.$metric })
                $stats[$metric] = Numeric-Summary $values
            }
            if ($adapterGroup.Count -lt 5) { $warnings.Add($mode+'/'+$phase+'/adapter '+$adapterGroup.Name+': fewer than five ADL samples; percentiles are not stable.') }
            $adapters += [ordered]@{
                adapter_index=$adapterGroup.Group[0].adapter_index
                n_samples=$adapterGroup.Count
                first_sample_utc=$adapterGroup.Group[0].data.timestamp_utc
                last_sample_utc=$adapterGroup.Group[-1].data.timestamp_utc
                metrics=$stats
            }
        }
        if ($matched.Count -eq 0) { $warnings.Add($mode+'/'+$phase+': no ADL samples overlap the measured interval.') }
        $frameStats = $null
        if ($null -ne $run.benchmark) {
            if ($phase -match '^biome_(.+)_stress$') { $frameStats=$run.benchmark.biome_stress.($Matches[1]) }
            else { $frameStats=$run.benchmark.$phase }
        }
        $phaseResults[$phase] = [ordered]@{
            intervals=$intervals
            n_samples=$matched.Count
            measured_frame_statistics=$frameStats
            adapters=$adapters
        }
    }
    $outputRuns += [ordered]@{mode=$mode;executable=$run.executable;executable_sha256=$run.executable_sha256;phases=$phaseResults}
}
$result = [ordered]@{
    schema=1
    generated_utc=[DateTime]::UtcNow.ToString('o')
    profile_directory=$profilePath
    profile_summary=$summaryPath
    telemetry_json=$telemetryPath
    telemetry_source=$telemetry.source
    telemetry_dll_version=$telemetry.dll_version
    requested_interval_ms=$telemetry.interval_ms
    adapters=$telemetry.adapters
    n_input_samples=$timedSamples.Count
    measured_phases=$phaseNames
    runs=$outputRuns
    warnings=@($warnings)
    notes=@(
        'ADL clocks, activity, temperatures and ASIC power are device-wide, not per-PID measurements. ASIC power is not whole-board power.'
        'Samples are matched by UTC/Unix wall-clock timestamps to [phase start, next event start). Loading, warmups, captures, galleries and all other phases are excluded.'
        'No background-application control or idle subtraction is performed; a device-wide difference cannot be attributed solely to the game process.'
        'Null means unavailable. Numeric zero is retained as reported, including clock-gating values. Percentiles use nearest rank.'
        'A point sample at a phase boundary can include driver averaging from the preceding interval. One-second telemetry is coarser than frame timings.'
        'Capped and uncapped modes differ in frame rate and may differ in DVFS/temperature. Their comparison alone does not establish an optimization power saving; compare matched builds, phases, frame caps, resolution and background workload.'
        'This script reads existing JSON only. It makes no GPU calls, launches and tuning changes.'
    )
}
if (-not $OutputJson) { $OutputJson=Join-Path $profilePath 'power-summary.json' }
$outputPath = [IO.Path]::GetFullPath($OutputJson)
$json = $result | ConvertTo-Json -Depth 45
[IO.File]::WriteAllText($outputPath,$json,[Text.UTF8Encoding]::new($false))
Write-Output $outputPath
foreach ($run in $outputRuns) {
    foreach ($phase in $phaseNames) {
        foreach ($adapter in $run.phases[$phase].adapters) {
            $power=$adapter.metrics.asic_power_w;$clock=$adapter.metrics.gfx_clock_mhz
            Write-Output ('{0}/{1}: N={2}; ASIC mean={3:F1}W, p95={4}W; core mean={5:F0}MHz, p95={6}MHz' -f $run.mode,$phase,$adapter.n_samples,$power.mean,$power.p95,$clock.mean,$clock.p95)
        }
    }
}
