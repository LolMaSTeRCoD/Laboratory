<#
.SYNOPSIS
Explicitly runs the finished native game, visibly, and profiles its own PID.
.EXAMPLE
 .\tools\run_graphics_profile.ps1 -Executable G:\Cady\KDTD.exe -ProfileName optimized
.EXAMPLE
 .\tools\run_graphics_profile.ps1 -Executable G:\Cady\Recovery\KDTD.previous.exe -ProfileName baseline
.NOTES
GPU samples are Windows per-PID 3D-engine counters, not whole-adapter load or
GPU frame timings. The script waits for the benchmark's automatic exit.
#>
[CmdletBinding()]
param(
 [Alias('ExePath')][string]$Executable='G:\Cady\KDTD.exe',
 [ValidatePattern('^[\p{L}\p{N}._-]+$')][string]$ProfileName='current',
 [ValidateSet('both','capped60','uncapped')][string]$Mode='both',
 [string]$OutputDirectory=(Join-Path $PSScriptRoot '..\Builds\GraphicsProfiles'),
 [string]$LegacyBenchmarkPath=(Join-Path $PSScriptRoot '..\Builds\render-benchmark.json'),
 [ValidateRange(250,10000)][int]$SampleIntervalMs=1000,
 [ValidateRange(30,3600)][int]$TimeoutSeconds=900,
 [switch]$ForceHighDetail,
 [switch]$GpuIsolation,
 [switch]$Quick,
 [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
$taskExe=(Resolve-Path -LiteralPath $Executable).Path
if ([IO.Path]::GetExtension($taskExe) -ne '.exe') {throw 'Executable must be a native .exe.'}
$taskModes=if ($Mode -eq 'both') {@('capped60','uncapped')} else {@($Mode)}
$taskOutput=[IO.Path]::GetFullPath($OutputDirectory)
$taskRoot=Join-Path $taskOutput ($ProfileName+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$taskCpuCount=[Environment]::ProcessorCount
function Quote-NativeArgument([string]$Value) {
 if ($Value.Contains('"')) {throw 'An argument contains a double quote.'}
 return '"'+$Value+'"'
}
function Numeric-Summary($Values) {
 $numbers=@($Values | Where-Object {$null -ne $_ -and (($_ -isnot [string]) -or $_ -ne '')} | ForEach-Object {[double]$_} | Sort-Object)
 if ($numbers.Count -eq 0) {return $null}
 return [ordered]@{samples=$numbers.Count;mean=($numbers|Measure-Object -Average).Average;p50=$numbers[[Math]::Max(0,[Math]::Ceiling($numbers.Count*.50)-1)];p95=$numbers[[Math]::Max(0,[Math]::Ceiling($numbers.Count*.95)-1)];max=$numbers[-1]}
}
function Read-PhaseEvents([string]$Path) {
 if (-not (Test-Path -LiteralPath $Path)) {return @()}
 $events=@()
 foreach ($line in [IO.File]::ReadAllLines($Path)) {
  if ($line -match 'RENDER_BENCHMARK_PHASE: (\{.*\})') {
   try {$events+=($Matches[1]|ConvertFrom-Json)} catch {}
  }
 }
 return $events
}
$plans=@()
foreach ($taskMode in $taskModes) {
 $taskRun=Join-Path $taskRoot $taskMode
 $taskJson=Join-Path $taskRun 'benchmark.json'
 $taskEngineLog=Join-Path $taskRun 'engine.log'
 $taskArgs=@('--log-file',$taskEngineLog,'--','--render-benchmark',('--benchmark-output='+$taskJson))
 if (-not $Quick) {$taskArgs+='--power-profile'}
 if ($taskMode -eq 'capped60') {$taskArgs+='--benchmark-capped'}
 if ($ForceHighDetail) {$taskArgs+='--force-high-detail'}
 if ($GpuIsolation) {$taskArgs+='--gpu-isolation'}
 $plans+=[ordered]@{mode=$taskMode;executable=$taskExe;arguments=$taskArgs;directory=$taskRun}
}
if ($ValidateOnly) {
 [ordered]@{validation_only=$true;visible_game_will_run=$false;plans=$plans}|ConvertTo-Json -Depth 8
 return
}
New-Item -ItemType Directory -Force -Path $taskRoot | Out-Null
$taskAdapters=@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name,DriverVersion,AdapterRAM,PNPDeviceID)
$taskAll=@()
foreach ($plan in $plans) {
 $taskRun=$plan.directory
 New-Item -ItemType Directory -Force -Path $taskRun | Out-Null
 $taskJson=Join-Path $taskRun 'benchmark.json'
 $taskEngineLog=Join-Path $taskRun 'engine.log'
 $taskStdout=Join-Path $taskRun 'stdout.log'
 $taskStderr=Join-Path $taskRun 'stderr.log'
 $taskArguments=($plan.arguments | ForEach-Object {Quote-NativeArgument $_}) -join ' '
 $taskStartedUtc=[DateTime]::UtcNow
 $taskStartedUnix=([DateTimeOffset]$taskStartedUtc).ToUnixTimeMilliseconds()/1000.0
 $taskTimer=[Diagnostics.Stopwatch]::StartNew()
 # This is an explicitly invoked final native benchmark, not a hidden helper.
 $taskProcess=Start-Process -FilePath $taskExe -ArgumentList $taskArguments -WorkingDirectory ([IO.Path]::GetDirectoryName($taskExe)) -WindowStyle Normal -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
 $taskProcessId=$taskProcess.Id
 Write-Host ('Profiling {0}: PID {1}; the game closes itself.' -f $plan.mode,$taskProcessId)
 $taskRows=[Collections.Generic.List[object]]::new()
 $taskLastCpu=0.0;$taskLastWall=0.0;$taskTimedOut=$false
 $taskGpuError=$null
 try {
  while (-not $taskProcess.HasExited) {
   if ($taskTimer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
    $taskTimedOut=$true
    # Stop only the process launched by this script, never another game instance.
    $taskProcess.Kill();$taskProcess.WaitForExit();break
   }
   $taskWall=$taskTimer.Elapsed.TotalMilliseconds
   $taskCpu=$null;$taskWorking=$null;$taskPrivate=$null
   try {
    $taskProcess.Refresh()
    $taskCpu=$taskProcess.TotalProcessorTime.TotalMilliseconds
    $taskWorking=$taskProcess.WorkingSet64/1MB
    $taskPrivate=$taskProcess.PrivateMemorySize64/1MB
   } catch {}
   $taskGpu=@();$taskGpuAll=@();$taskQueryOk=$true
   try {
    $taskFilter="Name LIKE 'pid_$($taskProcessId)_%'"
    $taskGpuAll=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter $taskFilter -ErrorAction Stop | Where-Object {$_.Name -match ('^pid_'+$taskProcessId+'_')})
    $taskGpu=@($taskGpuAll | Where-Object {$_.Name -match '_engtype_3D$'})
   } catch {$taskQueryOk=$false;$taskGpuError=$_.Exception.Message}
   $taskGpuValues=@($taskGpu | ForEach-Object {[double]$_.UtilizationPercentage})
   $taskCorePct=$null
   if ($null -ne $taskCpu -and $taskWall -gt $taskLastWall -and $taskRows.Count -gt 0) {$taskCorePct=100.0*($taskCpu-$taskLastCpu)/($taskWall-$taskLastWall)}
   $taskRows.Add([pscustomobject][ordered]@{
    utc=[DateTime]::UtcNow.ToString('o');unix_time=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0);elapsed_ms=$taskWall;phase='unknown';pid=$taskProcessId;mode=$plan.mode
    process_cpu_pct=if ($null -ne $taskCorePct) {$taskCorePct/$taskCpuCount} else {$null}
    process_cpu_one_core_pct=$taskCorePct;cpu_total_ms=$taskCpu;working_set_mib=$taskWorking;private_memory_mib=$taskPrivate
    gpu_3d_max_pct=if ($taskGpuValues.Count) {($taskGpuValues|Measure-Object -Maximum).Maximum} else {$null}
    gpu_3d_sum_pct=if ($taskGpuValues.Count) {($taskGpuValues|Measure-Object -Sum).Sum} else {$null}
    gpu_3d_engine_count=$taskGpu.Count;gpu_query_ok=$taskQueryOk
    gpu_engine_names=($taskGpu.Name -join '|')
    gpu_busiest_engine_pct=if ($taskGpuAll.Count) {($taskGpuAll.UtilizationPercentage|Measure-Object -Maximum).Maximum} else {$null}
    gpu_all_engines_json=ConvertTo-Json -InputObject @($taskGpuAll|Select-Object Name,UtilizationPercentage) -Compress
   })
   if ($null -ne $taskCpu) {$taskLastCpu=$taskCpu;$taskLastWall=$taskWall}
   Start-Sleep -Milliseconds $SampleIntervalMs
  }
  $taskProcess.WaitForExit()
 } catch {
  if (-not $taskProcess.HasExited) {$taskProcess.Kill();$taskProcess.WaitForExit()}
  throw
 } finally {$taskTimer.Stop()}
 $taskProcess.Refresh()
 $taskExitCode=$taskProcess.ExitCode
 $taskEvents=@(Read-PhaseEvents $taskEngineLog)
 if ($taskEvents.Count -eq 0) {$taskEvents=@(Read-PhaseEvents $taskStdout)}
 foreach ($row in $taskRows) {
  foreach ($event in $taskEvents) {if ([double]$event.unix_time -le [double]$row.unix_time) {$row.phase=$event.phase}}
 }
 $taskRows | Export-Csv -LiteralPath (Join-Path $taskRun 'samples.csv') -NoTypeInformation -Encoding UTF8
 $taskLegacy=$false
 if (-not (Test-Path -LiteralPath $taskJson) -and (Test-Path -LiteralPath $LegacyBenchmarkPath)) {
  $taskLegacyFile=Get-Item -LiteralPath $LegacyBenchmarkPath
  if ($taskLegacyFile.LastWriteTimeUtc -ge $taskStartedUtc.AddSeconds(-2)) {Copy-Item -LiteralPath $LegacyBenchmarkPath -Destination $taskJson;$taskLegacy=$true}
 }
 $taskBenchmark=$null
 if (Test-Path -LiteralPath $taskJson) {try {$taskBenchmark=Get-Content -LiteralPath $taskJson -Raw|ConvertFrom-Json} catch {}}
 $taskByPhase=[ordered]@{}
 foreach ($group in ($taskRows|Group-Object phase)) {
  $taskByPhase[$group.Name]=[ordered]@{samples=$group.Count;gpu_3d_engine_max_pct=Numeric-Summary $group.Group.gpu_3d_max_pct;gpu_3d_engine_sum_pct=Numeric-Summary $group.Group.gpu_3d_sum_pct;gpu_busiest_engine_pct=Numeric-Summary $group.Group.gpu_busiest_engine_pct;process_cpu_pct=Numeric-Summary $group.Group.process_cpu_pct;working_set_mib=Numeric-Summary $group.Group.working_set_mib;private_memory_mib=Numeric-Summary $group.Group.private_memory_mib}
 }
 $taskSummary=[ordered]@{
  schema=1;profile_name=$ProfileName;mode_requested=$plan.mode;executable=$taskExe;executable_sha256=(Get-FileHash -LiteralPath $taskExe -Algorithm SHA256).Hash;arguments=$plan.arguments
  started_utc=$taskStartedUtc.ToString('o');duration_seconds=$taskTimer.Elapsed.TotalSeconds;exit_code=$taskExitCode;timed_out=$taskTimedOut;logical_processors=$taskCpuCount
  force_high_detail_requested=[bool]$ForceHighDetail;power_profile_requested=(-not [bool]$Quick);legacy_fixed_output_copied=$taskLegacy
  gpu_adapters=$taskAdapters;gpu_counter_error=$taskGpuError;phase_events=$taskEvents;phase_correlation_available=($taskEvents.Count -gt 0)
  os_samples_by_phase=$taskByPhase;benchmark=$taskBenchmark
  notes=@('GPU values include only this PID and engtype_3D counters; they are not whole-adapter GPU load or GPU frame time.','Max is the busiest matching 3D engine. Sum may exceed 100 across engines/adapters. Missing counters remain null.','CPU percent is normalized by logical processor count. One-core percent can exceed 100.','Unknown/whole-process samples include loading, shader compilation, captures and galleries: do not label them stress-scene GPU utilization.','Compare matched phase, camera/resolution, active LOD counters, actual Engine.max_fps/VSync and build versions. Legacy binaries may ignore requested flags; inspect recorded benchmark metadata.','Fewer than five OS samples in a phase are insufficient for stable utilization percentiles.')
 }
 $taskSummary|ConvertTo-Json -Depth 35|Set-Content -LiteralPath (Join-Path $taskRun 'summary.json') -Encoding UTF8
 $taskAll+=$taskSummary
 Write-Host ('Saved {0}; exit={1}; samples={2}; correlated={3}' -f $taskRun,$taskExitCode,$taskRows.Count,($taskEvents.Count -gt 0))
}
[ordered]@{profile_name=$ProfileName;runs=$taskAll;output_directory=$taskRoot}|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $taskRoot 'summary.json') -Encoding UTF8
Write-Output $taskRoot
