param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$buildsRoot = [IO.Path]::GetFullPath('G:\Cady\GodotRebuild\Builds').TrimEnd('\')
$activeModels = 'G:\Cady\GodotRebuild\Assets\Heroes'
$workshops = @('hero-final-20261111','hero-final-revisions-20261111','charmy-final-costume-20261111')
$rows = @()
if ($Apply) {
    if ((Get-Item -LiteralPath 'G:\Cady\KDTD.exe').VersionInfo.FileVersion -ne '0.6.0.0') { throw 'Publish the checked 0.6.0 build before removing its workshop copies.' }
    if (-not (Select-String -LiteralPath (Join-Path $buildsRoot 'check-packed-spell-origins.log') -SimpleMatch 'SPELL_ORIGIN_OK' -Quiet)) { throw 'Packed model integration has not passed.' }
}
foreach ($workshop in $workshops) {
    $folder = [IO.Path]::GetFullPath((Join-Path $buildsRoot $workshop))
    if (-not $folder.StartsWith(($buildsRoot+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Workshop path escaped Builds.' }
    if (-not (Test-Path -LiteralPath $folder)) { continue }
    if ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a redirected workshop folder.' }
    foreach ($tileFolder in @('TexturesV4','Atlases')) {
        $candidate = [IO.Path]::GetFullPath((Join-Path $folder $tileFolder))
        if (-not $candidate.StartsWith(($folder+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe generated texture path.' }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $items = @(Get-Item -LiteralPath $candidate) + @(Get-ChildItem -LiteralPath $candidate -Recurse -Force)
        if ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Refusing to recurse through a reparse point.' }
        $bytes = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum
        $rows += [pscustomobject]@{path=$candidate;bytes=[long]$bytes;reason='Reproducible staging atlas/tiles; runtime GLB embeds maps and editable Blender images are packed.';removed=[bool]$Apply}
        if ($Apply) { Remove-Item -LiteralPath $candidate -Recurse -Force }
    }
    foreach ($file in Get-ChildItem -LiteralPath $folder -Filter '*.glb' -File) {
        $active = Join-Path $activeModels $file.Name
        if (-not (Test-Path -LiteralPath $active -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) { continue }
        $rows += [pscustomobject]@{path=$file.FullName;bytes=$file.Length;reason='Byte-identical copy of the validated active GLB.';removed=[bool]$Apply}
        if ($Apply) { Remove-Item -LiteralPath $file.FullName -Force }
    }
}
$report = @{applied=[bool]$Apply;generated_at=(Get-Date).ToString('o');bytes=($rows|Measure-Object bytes -Sum).Sum;items=$rows}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $buildsRoot 'quality-workshop-cleanup-20261111.json') -Encoding utf8
Write-Output ('WORKSHOP_CLEANUP: apply={0} bytes={1} entries={2}; source, checkpoints and QA renders retained' -f $Apply,$report.bytes,$rows.Count)
