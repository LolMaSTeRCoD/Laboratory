[CmdletBinding()]
param(
    [string]$PlanPath = 'G:\Cady\GodotRebuild\Builds\disk-cleanup-plan.json',
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
$rootPath = 'G:\Cady'
$scriptRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
if (-not $scriptRoot.Equals([IO.Path]::GetFullPath($rootPath).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) {
    throw "Historical cleanup is disabled after relocation: its reviewed manifests belong to $rootPath. Regenerate and review cleanup plans for $scriptRoot before enabling cleanup."
}
$projectPath = Join-Path $rootPath 'GodotRebuild'
$rootPrefix = [IO.Path]::GetFullPath($rootPath).TrimEnd('\') + '\'
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
$assetAudit = Get-Content -LiteralPath (Join-Path $projectPath 'Builds\asset-cleanup-candidates.json') -Raw | ConvertFrom-Json
$runtime = Get-Content -LiteralPath (Join-Path $projectPath 'Builds\export-runtime-manifest.json') -Raw | ConvertFrom-Json
$sourceAudit = Get-Content -LiteralPath (Join-Path $projectPath 'Builds\source-blender-image-dependencies.json') -Raw | ConvertFrom-Json
$validation = Get-Content -LiteralPath (Join-Path $projectPath 'Builds\final-validation.json') -Raw | ConvertFrom-Json
$recovery = Get-Content -LiteralPath (Join-Path $rootPath 'Archive\Recovery\recovery.json') -Raw | ConvertFrom-Json
$release = Get-Content -LiteralPath (Join-Path $projectPath 'Builds\Release\KDTD-Windows.zip.json') -Raw | ConvertFrom-Json
$reportPath = Join-Path $projectPath 'Builds\cleanup-execution.json'
$journalPath = Join-Path $projectPath 'Builds\cleanup-deleted-files.jsonl'

function Canonical([string]$Path) {
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "Non-absolute path: $Path" }
    return [IO.Path]::GetFullPath($Path)
}
function From-Resource([string]$Path) {
    if (-not $Path.StartsWith('res://')) { throw "Unexpected resource path: $Path" }
    return Canonical (Join-Path $projectPath $Path.Substring(6))
}
function Assert-LocalFile([string]$Path) {
    $full = Canonical $Path
    if (-not $full.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Outside intended project root: $full" }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing file: $full" }
    # Check every ancestor as well as the file: a lexical prefix alone is not
    # sufficient if a junction redirects an intermediate directory elsewhere.
    $item = Get-Item -LiteralPath $full -Force
    while ($null -ne $item) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in cleanup path: $($item.FullName)" }
        if ($item.FullName.TrimEnd('\') -ieq $rootPath) { break }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
}

if (@(Get-Process -Name KDTD,blender,Godot* -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Close game/model/import processes before cleanup.' }
if ((Get-FileHash -LiteralPath $validation.executable -Algorithm SHA256).Hash -ne $validation.sha256) { throw 'Current executable differs from tested build.' }
if ((Get-FileHash -LiteralPath $recovery.Path -Algorithm SHA256).Hash -ne $recovery.SHA256) { throw 'Recovery executable is not verified.' }
if ((Get-FileHash -LiteralPath $release.archive -Algorithm SHA256).Hash -ne $release.archive_sha256) { throw 'Release ZIP differs from verified archive.' }

$protected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($validation.executable,$recovery.Path,$release.archive,
    'G:\Cady\Tools\Blender\blender-5.2.3-windows-x64\blender.exe',
    'G:\Cady\Tools\Godot\Godot_v4.7.2-stable_win64.exe',
    'G:\Cady\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe')) { [void]$protected.Add((Canonical $path)) }
foreach ($resource in @($runtime.resources)+@($runtime.character_runtime_keep)+@($runtime.transitive_dependencies)+@($runtime.data_files)) {
    if ($resource -isnot [string] -or -not $resource.StartsWith('res://')) { continue }
    $path = From-Resource $resource
    if (Test-Path -LiteralPath $path -PathType Leaf) { [void]$protected.Add($path) }
    $sidecar = $path + '.import'
    if (Test-Path -LiteralPath $sidecar -PathType Leaf) {
        [void]$protected.Add($sidecar)
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($sidecar),'res://\.godot/imported/[^"\r\n]+')) {
            $cache = From-Resource $match.Value
            if (Test-Path -LiteralPath $cache -PathType Leaf) { [void]$protected.Add($cache) }
            $md5 = [IO.Path]::ChangeExtension($cache,'.md5')
            if (Test-Path -LiteralPath $md5 -PathType Leaf) { [void]$protected.Add($md5) }
        }
    }
}
foreach ($blend in $sourceAudit.blend_files) {
    [void]$protected.Add((Canonical $blend.path))
    foreach ($image in $blend.images) {
        if (-not $image.packed -and $image.resolved -and (Test-Path -LiteralPath $image.resolved -PathType Leaf)) { [void]$protected.Add((Canonical $image.resolved)) }
    }
}

$generatedAllow = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($candidate in $assetAudit.unused_generated_png_candidates) {
    if (-not $candidate.import_is_generated) { throw 'An image candidate is not marked as generated.' }
    foreach ($path in @($candidate.source,$candidate.import_sidecar,(From-Resource $candidate.cache_resource),([IO.Path]::ChangeExtension((From-Resource $candidate.cache_resource),'.md5')))) { [void]$generatedAllow.Add((Canonical $path)) }
}
$otherAllow = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($path in @('G:\Cady\Tools\blender-5.2.3-windows-x64.zip','G:\Cady\Tools\Godot_v4.7.2-stable_win64.exe.zip','G:\Cady\GodotRebuild\Builds\runtime-package-check.pck')) { [void]$otherAllow.Add($path) }

$targets = [Collections.Generic.List[object]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in $plan.files) {
    $path = Canonical $entry.Path
    if (-not $seen.Add($path)) { throw "Duplicate cleanup path: $path" }
    $isLegacy = [IO.Path]::GetDirectoryName($path) -ieq 'G:\Cady\Archive\LegacyBuilds' -and [IO.Path]::GetExtension($path) -ieq '.exe'
    if (-not $generatedAllow.Contains($path) -and -not $otherAllow.Contains($path) -and -not $isLegacy) { throw "File is outside the explicit cleanup categories: $path" }
    if ($protected.Contains($path)) { throw "Cleanup intersects an active/source dependency: $path" }
    Assert-LocalFile $path
    $file = Get-Item -LiteralPath $path -Force
    if ($file.Length -ne [long]$entry.Bytes) { throw "Candidate size changed since review: $path" }
    $targets.Add([pscustomobject]@{Path=$path;Bytes=$file.Length;Category=$entry.Category})
}
if ($targets.Count -ne [int]$plan.total_files -or ($targets | Measure-Object Bytes -Sum).Sum -ne [long]$plan.total_bytes) { throw 'Cleanup totals differ from reviewed plan.' }

$protectedSnapshot = @($protected | Sort-Object | ForEach-Object { [pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} })
$report = [ordered]@{
    timestamp=(Get-Date).ToString('o');authorization='User explicitly consented to cleanup after the optimization report';
    executed=$false;status='preflight-passed';plan=$PlanPath;planned_files=$targets.Count;
    planned_bytes=[long]($targets|Measure-Object Bytes -Sum).Sum;deleted_files=0;deleted_bytes=0;
    protected_files=$protectedSnapshot.Count;protected_hashes=$protectedSnapshot;errors=@()
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
if (-not $Execute) { Write-Output ("CLEANUP_PREFLIGHT_OK: {0} exact files, {1} bytes; {2} protected file hashes; no deletions." -f $targets.Count,$report.planned_bytes,$protectedSnapshot.Count); return }

try {
    foreach ($target in $targets) {
        # No globbing, directory removal, recursive deletion or shell crossing.
        # Each literal file was checked against active resources and sources.
        Remove-Item -LiteralPath $target.Path -Force -ErrorAction Stop
        $report.deleted_files++
        $report.deleted_bytes += [long]$target.Bytes
        $target | ConvertTo-Json -Compress | Add-Content -LiteralPath $journalPath -Encoding UTF8
    }
    foreach ($entry in $protectedSnapshot) {
        if ((Get-FileHash -LiteralPath $entry.Path -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Protected file hash changed: $($entry.Path)" }
    }
    $report.executed=$true
    $report.status='complete'
} catch {
    $report.status='incomplete'
    $report.errors+= $_.Exception.Message
    throw
} finally {
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}
Write-Output ("CLEANUP_COMPLETE: {0} files, {1} bytes freed; all protected hashes unchanged." -f $report.deleted_files,$report.deleted_bytes)
