param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')
if ($root -ine 'E:\Laboratory') { throw 'This reviewed cleanup is valid only in E:\Laboratory.' }
$builds = Join-Path $root 'GodotRebuild\Builds'
$reportPath = Join-Path $builds 'cleanup-20261115-plan.json'
$tracked = @(git -C $root ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot read tracked-file protection list.' }

function Assert-CachePath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($builds+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Outside Builds: $full" }
    $cursor = $full
    while ($cursor.Length -ge $root.Length) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Redirected path: $cursor" }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
        if (-not $cursor) { break }
    }
    $relative = $full.Substring($root.Length+1).Replace('\','/')
    foreach ($file in $tracked) {
        if ($file -ieq $relative -or $file.StartsWith($relative+'/',[StringComparison]::OrdinalIgnoreCase)) { throw "Tracked data protected: $full" }
    }
    return $full
}

$directories = [Collections.Generic.List[string]]::new()
$files = [Collections.Generic.List[string]]::new()
$latest = @('back-final','candidate','cape-final','final','final2','final3','grip-final','v1','v2','v3-other','vanessa-lace','waist-final','waist-final2','yuno-tail-final')
foreach ($batch in $latest) {
    foreach ($part in @('runtime','editable')) {
        $path = Join-Path $builds ('likeness-20261113\'+$batch+'\'+$part)
        if (Test-Path -LiteralPath $path -PathType Container) { $directories.Add((Assert-CachePath $path)) }
    }
}
$older = @('portrait-final-20261111','portrait-study-20261110','hero-final-20261111','enemy-quality-finish-20261111','enemy-refinement-20261110','costume-study-v2-20261110','costume-study-20261110')
foreach ($batch in $older) {
    $path = Join-Path $builds $batch
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    Assert-CachePath $path | Out-Null
    $items = @(Get-ChildItem -LiteralPath $path -Recurse -Force)
    if ($items | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}) { throw "Redirected workshop item: $path" }
    foreach ($item in $items) {
        if ($item.PSIsContainer -and $item.Name -in @('Atlases','TexturesV2','TexturesV3','TexturesV4','__pycache__')) {
            $directories.Add((Assert-CachePath $item.FullName))
        } elseif (-not $item.PSIsContainer -and ($item.Extension -ieq '.glb' -or $item.Name -match '\.blend\d*$')) {
            $files.Add((Assert-CachePath $item.FullName))
        }
    }
}
foreach ($name in @('character-lod-work','yuno-l5-lod-qa-input.json','asta-l5-lod-qa-input.json')) {
    $path = Join-Path $builds $name
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).PSIsContainer) { $directories.Add((Assert-CachePath $path)) }
        else { $files.Add((Assert-CachePath $path)) }
    }
}
# Keep only top-level targets; no child is counted or deleted twice.
$targets = [Collections.Generic.List[string]]::new()
foreach ($path in @($directories | Sort-Object Length, @{Expression={$_}} -Unique)) {
    if (-not @($targets | Where-Object {$path.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count) { $targets.Add($path) }
}
foreach ($path in @($files | Sort-Object -Unique)) {
    if (-not @($targets | Where-Object {$path.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)}).Count) { $targets.Add($path) }
}
$rows = foreach ($path in $targets) {
    $item = Get-Item -LiteralPath (Assert-CachePath $path) -Force
    $content = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $path -Recurse -Force) } else { @($item) }
    if ($content | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}) { throw "Redirected descendant: $path" }
    $data = @($content | Where-Object {-not $_.PSIsContainer})
    [pscustomobject]@{path=$path;directory=[bool]$item.PSIsContainer;files=$data.Count;bytes=[long](($data|Measure-Object Length -Sum).Sum)}
}
$plan = [ordered]@{root=$root;date=(Get-Date).ToString('o');apply=[bool]$Apply;bytes=[long](($rows|Measure-Object bytes -Sum).Sum);files=[long](($rows|Measure-Object files -Sum).Sum);targets=@($rows);preserved=@('KDTD.exe','Source','Assets','GodotRebuild/Assets','.git and LFS','Tools','Archive/Recovery','Builds/Release','all review images, diagnostic logs and reports','.godot import cache')}
if ($Apply) {
    if (Get-Process -Name 'blender','Godot*' -ErrorAction SilentlyContinue) { throw 'Asset/editor process is active; postpone cache cleanup.' }
    $review = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $reviewSignature = @($review.targets | ForEach-Object { '{0}|{1}|{2}' -f $_.path,$_.files,$_.bytes }) -join "`n"
    $currentSignature = @($rows | ForEach-Object { '{0}|{1}|{2}' -f $_.path,$_.files,$_.bytes }) -join "`n"
    if ($reviewSignature -cne $currentSignature) { throw 'Cache contents changed after review. Regenerate and inspect the plan.' }
    $checkpoint = Join-Path $builds 'cleanup-20261115-checkpoint.json'
    if (-not (Test-Path -LiteralPath $checkpoint)) { throw 'Create a local source checkpoint before applying cleanup.' }
    $saved = Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json
    $savedRef = git -C $root rev-parse $saved.branch
    if ($LASTEXITCODE -ne 0 -or $savedRef -cne $saved.commit) { throw 'Source checkpoint reference is missing or changed.' }
    $meta = Get-Content -LiteralPath (Join-Path $builds 'Release\KDTD-Windows.zip.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath (Join-Path $root 'KDTD.exe')).Hash -ne $meta.executable_sha256) { throw 'Current EXE does not match verified release.' }
    $enemyAudit = Get-Content -LiteralPath (Join-Path $builds 'cleanup-20261115-enemy-sources.json') -Raw | ConvertFrom-Json
    if (-not $enemyAudit.passed) { throw 'Enemy editable source dependencies have not passed.' }
    $promotion = Get-Content -LiteralPath (Join-Path $builds 'likeness-20261113\final3\promotion.json') -Raw | ConvertFrom-Json
    foreach ($entry in $promotion.files) {
        $path = Join-Path $root $entry.file
        if ((Get-FileHash -LiteralPath $path).Hash -ine $entry.sha256) { throw "Canonical file changed since verified promotion: $path" }
    }
    foreach ($row in $rows) {
        Assert-CachePath $row.path | Out-Null
        if ($row.directory) { Remove-Item -LiteralPath $row.path -Recurse -Force }
        else { Remove-Item -LiteralPath $row.path -Force }
    }
    $plan['completed'] = $true
    $reportPath = Join-Path $builds 'cleanup-20261115-result.json'
}
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output ('CACHE_CLEANUP: apply={0} targets={1} files={2} bytes={3} report={4}' -f $Apply,$rows.Count,$plan.files,$plan.bytes,$reportPath)
