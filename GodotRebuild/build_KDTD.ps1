param(
    [string]$OutputPath,
    [switch]$ReuseModels,
    [string]$GodotPath = $env:KDTD_GODOT,
    [string]$BlenderPath = $env:KDTD_BLENDER,
    [string]$BlenderPythonPath = $env:KDTD_BLENDER_PYTHON,
    [string]$TemplatePath = $env:KDTD_EXPORT_TEMPLATES
)

$ErrorActionPreference = 'Stop'

$Project = [System.IO.Path]::GetFullPath($PSScriptRoot)
$RepositoryRoot = [System.IO.Path]::GetDirectoryName($Project)

function Resolve-BuildExecutable([string]$ExplicitPath,[string[]]$Candidates,[string[]]$Commands,[string]$Label,[string]$OverrideName) {
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $expanded = [Environment]::ExpandEnvironmentVariables($ExplicitPath)
        if (Test-Path -LiteralPath $expanded -PathType Leaf) { return [System.IO.Path]::GetFullPath($expanded) }
        $command = Get-Command $expanded -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
        throw "$Label override was not found: $ExplicitPath. Set $OverrideName to an installed executable."
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return [System.IO.Path]::GetFullPath($candidate) }
    }
    foreach ($name in $Commands) {
        $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    throw "$Label was not found. Install it locally under Tools, add it to PATH, or set $OverrideName."
}

$localGodot = Join-Path $RepositoryRoot 'Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$Godot = Resolve-BuildExecutable $GodotPath @($localGodot) @('godot4_console.exe','godot_console.exe','godot4.exe','godot.exe') 'Godot console binary' 'KDTD_GODOT/-GodotPath'
$blenderCandidates = @((Join-Path $RepositoryRoot 'Tools\Blender\blender-5.2.3-windows-x64\blender.exe'))
$blenderCandidates += @(Get-ChildItem -Path (Join-Path $RepositoryRoot 'Tools\Blender\*\blender.exe') -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
if ($env:ProgramFiles) {
    $blenderCandidates += @(Get-ChildItem -Path (Join-Path $env:ProgramFiles 'Blender Foundation\Blender*\blender.exe') -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
}
$Blender = Resolve-BuildExecutable $BlenderPath $blenderCandidates @('blender.exe') 'Blender' 'KDTD_BLENDER/-BlenderPath'
$blenderDirectory = [System.IO.Path]::GetDirectoryName($Blender)
$pythonCandidates = @(Get-ChildItem -Path (Join-Path $blenderDirectory '*\python\bin\python.exe') -File -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
$BlenderPython = Resolve-BuildExecutable $BlenderPythonPath $pythonCandidates @() 'Blender Python (with NumPy)' 'KDTD_BLENDER_PYTHON/-BlenderPythonPath'
if ([string]::IsNullOrWhiteSpace($env:KDTD_NODE)) {
    $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeCommand) { $env:KDTD_NODE = $nodeCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $RepositoryRoot 'KDTD.exe' }
$Output = [System.IO.Path]::GetFullPath($OutputPath)
$PermanentOutput = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'KDTD.exe'))
$OutputDirectory = [System.IO.Path]::GetDirectoryName($Output)
$StageDirectory = Join-Path $Project 'Builds'
$StageOutput = Join-Path $StageDirectory 'KDTD-staging.exe'
$PublishTemp = $Output + '.new'
if ([string]::IsNullOrWhiteSpace($TemplatePath)) { $TemplatePath = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable' }
$TemplateDir = [System.IO.Path]::GetFullPath($TemplatePath)
$RecoveryDirectory = Join-Path $RepositoryRoot 'Archive\Recovery'
$PackageInspector = Join-Path ([System.IO.Path]::GetTempPath()) ("KDTD-package-inspector-" + $PID)

function Assert-GodotLog([string]$Path,[string]$Label) {
    # Godot can print script/resource errors and still exit with code zero.
    # Do not publish a build solely because its process returned successfully.
    if (-not (Test-Path -LiteralPath $Path)) { throw "$Label did not create its diagnostic log: $Path" }
    if (Test-Path -LiteralPath $Path) {
        $problems = Select-String -LiteralPath $Path -Pattern 'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked'
        if ($problems) {
            throw "$Label reported engine errors or unreleased objects. See $Path"
        }
    }
}

function Invoke-GodotCheck([string]$Label,[string[]]$Arguments,[string]$LogName) {
    $checkLog = Join-Path $StageDirectory $LogName
    # A successful --quiet export may produce no output at all. Create the
    # empty log first; Tee-Object alone does not create it without input.
    [System.IO.File]::WriteAllText($checkLog,'')
    & $Godot @Arguments 2>&1 | Tee-Object -FilePath $checkLog -Append
    $checkExit = $LASTEXITCODE
    if ($checkExit -ne 0) { throw "$Label failed with exit code $checkExit. See $checkLog" }
    Assert-GodotLog $checkLog $Label
}

function Remove-FileWithRetry([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 5) {
                Write-Warning "Temporary build file is still locked and was left in place: $Path"
                return
            }
            Start-Sleep -Milliseconds 300
        }
    }
}

if (-not (Test-Path -LiteralPath $Project)) { throw "Project directory not found: $Project" }
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot console binary not found: $Godot" }
if (-not (Test-Path -LiteralPath $Blender)) { throw "Blender is required to rebuild the skinned 3D models: $Blender" }
if (-not (Test-Path -LiteralPath (Join-Path $TemplateDir 'windows_release_x86_64.exe'))) {
    throw "Godot 4.7.2 Windows release export template is missing: $TemplateDir"
}

New-Item -ItemType Directory -Path $StageDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$BuildLock = [System.IO.File]::Open((Join-Path $StageDirectory 'KDTD-build.lock'),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
try {
foreach ($temporaryFile in @($StageOutput,$PublishTemp)) {
    Remove-FileWithRetry $temporaryFile
}

    if (-not $ReuseModels) {
    Write-Host 'Building the seven rigged enemy GLB models, including the arena boss…'
    & $Blender --background --python-exit-code 1 --python (Join-Path $Project 'tools\build_enemy_assets.py')
    if ($LASTEXITCODE -ne 0) { throw "Enemy model generation failed with exit code $LASTEXITCODE" }

    Write-Host 'Building the 30 anatomical tower character variants from the new pipeline…'
    & $Blender --background --python-exit-code 1 --python (Join-Path $Project 'tools\build_hero_assets.py')
    if ($LASTEXITCODE -ne 0) { throw "Tower model generation failed with exit code $LASTEXITCODE" }
    } else {
        Write-Host 'Using prepared GLB assets; all model and gameplay checks still run.'
    }

    Write-Host 'Auditing native hero GLB skins, weights, animation data and embedded materials…'
    & $BlenderPython (Join-Path $Project 'tools\audit_hero_glbs.py') (Join-Path $Project 'Assets\Heroes') (Join-Path $StageDirectory 'check-hero-glb-contracts.json') 2>&1 | Tee-Object -FilePath (Join-Path $StageDirectory 'check-hero-glb-contracts.log')
    if ($LASTEXITCODE -ne 0) { throw 'Native hero GLB audit failed.' }

    Write-Host 'Importing project resources…'
    Invoke-GodotCheck 'Resource import' @('--headless','--editor','--path',$Project,'--quit') 'check-import.log'

    Invoke-GodotCheck 'Imported hero atlas integrity' @('--headless','--path',$Project,'--script','res://tests/hero_import_textures_smoke.gd') 'check-hero-import-textures.log'

    Write-Host 'Preparing compact skinned character meshes for distant views…'
    Invoke-GodotCheck 'Character LOD build' @('--headless','--path',$Project,'--script','res://tools/build_character_lods.gd') 'check-build-lods.log'
    Invoke-GodotCheck 'Character LOD import' @('--headless','--editor','--path',$Project,'--quit') 'check-import-lods.log'
    Invoke-GodotCheck 'Character LOD regression' @('--headless','--path',$Project,'--script','res://tests/character_lod_smoke.gd') 'check-character-lods.log'
    Invoke-GodotCheck 'Character animation LOD regression' @('--headless','--path',$Project,'--script','res://tests/character_animation_lod_smoke.gd') 'check-character-animation-lods.log'

    Write-Host 'Checking enemy meshes, skins, skeletons and animation clips…'
    Invoke-GodotCheck 'Enemy rig test' @('--headless','--path',$Project,'--script','res://tests/enemy_models_smoke.gd') 'check-enemy-models.log'

    Write-Host 'Checking all tower meshes, rigs, animations and upgrade variants…'
    Invoke-GodotCheck 'Tower rig test' @('--headless','--path',$Project,'--script','res://tests/tower_models_smoke.gd') 'check-tower-models.log'
    Invoke-GodotCheck 'Animated spell origins' @('--headless','--path',$Project,'--script','res://tests/spell_origin_smoke.gd') 'check-spell-origins.log'

    Write-Host 'Checking all campaign layouts, buildable grass, hamlets and caves…'
    Invoke-GodotCheck 'World layout test' @('--headless','--path',$Project,'--script','res://tests/world_layout_smoke.gd') 'check-world-layout.log'
    Invoke-GodotCheck 'World render batching' @('--headless','--path',$Project,'--script','res://tests/world_render_optimization_smoke.gd') 'check-world-render.log'

    Write-Host 'Checking 360-degree camera projection, map fit and mouse release…'
    Invoke-GodotCheck 'Camera orbit test' @('--headless','--path',$Project,'--script','res://tests/camera_orbit_smoke.gd') 'check-camera.log'

    Write-Host 'Checking enemy health indicators at rotated camera angles and parent scales…'
    Invoke-GodotCheck 'Health bar orientation test' @('--headless','--path',$Project,'--script','res://tests/health_bar_smoke.gd') 'check-health-bars.log'

    Write-Host 'Running placement, aura and combat regression test…'
    Invoke-GodotCheck 'Placement/combat test' @('--headless','--path',$Project,'--script','res://tests/placement_combat_smoke.gd') 'check-placement-combat.log'

    Write-Host 'Checking compact UI layouts and ten-percent campaign carryover…'
    Invoke-GodotCheck 'UI and campaign economy' @('--headless','--path',$Project,'--script','res://tests/ui_economy_smoke.gd') 'check-ui-economy.log'
    Invoke-GodotCheck 'Tower and enemy inspection layouts' @('--headless','--path',$Project,'--script','res://tests/inspection_layout_smoke.gd') 'check-inspection-layout.log'
    Invoke-GodotCheck 'Combat rules and enemy inspection' @('--headless','--path',$Project,'--script','res://tests/combat_rules_smoke.gd') 'check-combat-rules.log'
    Invoke-GodotCheck 'Frame pacing and settings' @('--headless','--path',$Project,'--script','res://tests/frame_pacing_smoke.gd') 'check-frame-pacing.log'
    Invoke-GodotCheck 'Bundled music loading' @('--headless','--path',$Project,'--script','res://tests/bundled_music_smoke.gd') 'check-bundled-music.log'

    Write-Host 'Checking minimum-budget first-wave scenarios on early and late maps…'
    Invoke-GodotCheck 'Campaign opening balance' @('--headless','--path',$Project,'--script','res://tests/first_wave_balance_sim.gd') 'check-campaign-opening.log'
    Invoke-GodotCheck 'Campaign battle diagnostics' @('--headless','--path',$Project,'--script','res://tests/campaign_balance_probe.gd') 'check-campaign-battle.log'

    Write-Host 'Running headless wave-load profile…'
    Invoke-GodotCheck 'Performance profile' @('--headless','--path',$Project,'--script','res://tests/performance_smoke.gd') 'check-performance.log'

    Write-Host 'Selecting only resources used by the playable game…'
    Invoke-GodotCheck 'Runtime export manifest' @('--headless','--path',$Project,'--script','res://tools/update_export_manifest.gd') 'check-export-manifest-update.log'
    Invoke-GodotCheck 'Runtime export dependencies' @('--headless','--path',$Project,'--script','res://tests/export_manifest_smoke.gd') 'check-export-manifest.log'

    Write-Host 'Exporting a staging build…'
    Invoke-GodotCheck 'Windows export' @('--headless','--quiet','--path',$Project,'--export-release','Windows Desktop',$StageOutput) 'check-export.log'
    if (-not (Test-Path -LiteralPath $StageOutput)) { throw 'Godot did not produce the staging executable.' }
    if ((Get-Item -LiteralPath $StageOutput).Length -lt 80000000) { throw 'Staging executable is unexpectedly small; embedded game data may be missing.' }

    Write-Host 'Checking the staging executable in headless mode…'
    # Windows GUI executables can return control to PowerShell before they exit.
    # Wait explicitly so startup failures and file locks are observed correctly.
    $StageLog = Join-Path $StageDirectory 'check-staging-exe.log'
    $StageProcess = Start-Process -FilePath $StageOutput -ArgumentList @('--headless','--log-file',($StageLog -replace '\\','/'),'--quit-after','4') -WindowStyle Hidden -Wait -PassThru
    if ($StageProcess.ExitCode -ne 0) { throw "Staging executable startup check failed with exit code $($StageProcess.ExitCode)" }
    Assert-GodotLog $StageLog 'Staging executable startup'

    Write-Host 'Deserializing all packed characters, LODs, maps and audio in isolation…'
    New-Item -ItemType Directory -Path $PackageInspector -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $PackageInspector 'project.godot'),"config_version=5`n")
    Invoke-GodotCheck 'Embedded package integrity' @('--headless','--path',$PackageInspector,'--script',(Join-Path $Project 'tools\validate_export_package.gd'),'--',$StageOutput,(Join-Path $StageDirectory 'export-runtime-manifest.json'),(Join-Path $StageDirectory 'check-package-integrity.json')) 'check-package-integrity.log'
    # The standard release template disables external --script overrides.
    # Use the identical Godot host with the staging PCK as its only project;
    # all runtime code, materials, rigs and maps still come from that EXE.
    Invoke-GodotCheck 'Packed placement and battle UI' @('--headless','--path',$PackageInspector,'--main-pack',$StageOutput,'--script',(Join-Path $Project 'tests\placement_combat_smoke.gd')) 'check-packed-placement.log'
    Invoke-GodotCheck 'Packed Charmy and enemy inspection' @('--headless','--path',$PackageInspector,'--main-pack',$StageOutput,'--script',(Join-Path $Project 'tests\packaged_charmy_inspection_smoke.gd')) 'check-packed-charmy.log'
    Invoke-GodotCheck 'Packed animated spell origins' @('--headless','--path',$PackageInspector,'--main-pack',$StageOutput,'--script',(Join-Path $Project 'tests\spell_origin_smoke.gd')) 'check-packed-spell-origins.log'

    if ($Output -eq $PermanentOutput) {
        $runningBuild = Get-Process -Name 'KDTD' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -ieq $Output) }
        if ($runningBuild) { throw 'KDTD.exe is still running. Close the game and run the build again; the running process was left untouched.' }
    }

    Copy-Item -LiteralPath $StageOutput -Destination $PublishTemp -Force
    if (Test-Path -LiteralPath $Output) {
        if ($Output -eq $PermanentOutput) {
            # Keep one recovery build instead of accumulating hundreds of MB
            # on every export. This runs only after all staging checks pass.
            New-Item -ItemType Directory -Path $RecoveryDirectory -Force | Out-Null
            $backupPath = Join-Path $RecoveryDirectory 'KDTD.previous.exe'
        } else {
            $backupPath = $Output + '.previous'
        }
        [System.IO.File]::Replace($PublishTemp,$Output,$backupPath)
    } else {
        [System.IO.File]::Move($PublishTemp,$Output)
    }

    if ($Output -eq $PermanentOutput) {
        $recoveryFile = Join-Path $RecoveryDirectory 'KDTD.previous.exe'
        if (Test-Path -LiteralPath $recoveryFile) {
            @{
                Path = $recoveryFile
                SHA256 = (Get-FileHash -LiteralPath $recoveryFile -Algorithm SHA256).Hash
                Version = (Get-Item -LiteralPath $recoveryFile).VersionInfo.FileVersion
                Date = (Get-Date).ToString('o')
            } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RecoveryDirectory 'recovery.json') -Encoding UTF8
        }
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path $RepositoryRoot 'KDTD.lnk'))
        $shortcut.TargetPath = $Output
        $shortcut.WorkingDirectory = $RepositoryRoot
        $shortcut.IconLocation = "$Output,0"
        $shortcut.Description = 'Коди TD — Рубеж Средиземья'
        $shortcut.Save()
        Write-Host 'Updating the verified Windows distribution archive…'
        & (Join-Path $Project 'tools\package_release.ps1') -Executable $Output
    }

    Write-Host "Build complete: $Output"
    Write-Host ("Size: {0:N1} MB" -f ((Get-Item -LiteralPath $Output).Length / 1MB))
} finally {
    try {
    foreach ($temporaryFile in @($StageOutput,$PublishTemp)) {
        Remove-FileWithRetry $temporaryFile
    }
    if (Test-Path -LiteralPath $PackageInspector) {
        $resolvedInspector = [System.IO.Path]::GetFullPath($PackageInspector)
        $expectedInspectorRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\KDTD-package-inspector-'
        if (-not $resolvedInspector.StartsWith($expectedInspectorRoot,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe inspector cleanup path.' }
        Remove-Item -LiteralPath $resolvedInspector -Recurse -Force
    }
    } finally { $BuildLock.Dispose() }
}
