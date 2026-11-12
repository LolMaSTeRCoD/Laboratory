param(
    [string]$ExternalRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GitHub\External'),
    [switch]$CheckOnly,
    [switch]$InitializeSubmodules
)
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$manifest = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'development-tools.lock.json') -Raw | ConvertFrom-Json
$Git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$ExternalRoot = [IO.Path]::GetFullPath($ExternalRoot)
if (-not $CheckOnly) { New-Item -ItemType Directory -Path $ExternalRoot -Force | Out-Null }

function Invoke-SourceGit([string[]]$CommandArguments) {
    & $Git @CommandArguments
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($CommandArguments -join ' ')" }
}

foreach ($source in $manifest.repositories) {
    if ($source.name -notmatch '^[A-Za-z0-9_.-]+$' -or $source.commit -notmatch '^[0-9a-f]{40}$' -or $source.url -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$') {
        throw 'Invalid source entry in development-tools.lock.json.'
    }
    $target = Join-Path $ExternalRoot $source.name
    if (-not (Test-Path -LiteralPath $target)) {
        if ($CheckOnly) { throw "Missing source checkout: $target" }
        Invoke-SourceGit @('clone','--depth','1','--',$source.url,$target)
        $head = (Invoke-SourceGit @('-C',$target,'rev-parse','HEAD') | Out-String).Trim()
        if ($head -ne $source.commit) {
            Invoke-SourceGit @('-C',$target,'fetch','--depth','1','origin',$source.commit)
            Invoke-SourceGit @('-C',$target,'checkout','--detach',$source.commit)
        }
    } elseif (-not (Test-Path -LiteralPath (Join-Path $target '.git'))) {
        throw "Existing non-Git folder will not be overwritten: $target"
    }

    $origin = (Invoke-SourceGit @('-C',$target,'remote','get-url','origin') | Out-String).Trim()
    if ($origin.TrimEnd('/') -ine $source.url.TrimEnd('/')) { throw "Unexpected origin for $target; left untouched." }
    $head = (Invoke-SourceGit @('-C',$target,'rev-parse','HEAD') | Out-String).Trim()
    if ($head -ne $source.commit) { throw "Existing checkout differs from the locked commit: $target; left untouched." }
    $changes = Invoke-SourceGit @('-C',$target,'status','--porcelain')
    if ($changes) { throw "Existing checkout has local changes: $target; left untouched." }
    if ($InitializeSubmodules -and -not $CheckOnly) {
        Invoke-SourceGit @('-C',$target,'submodule','update','--init','--recursive','--depth','1')
    }
    Write-Output ("SOURCE_OK: {0} {1}" -f $source.name,$head)
}
Write-Output ("EXTERNAL_SOURCES_OK: {0} repositories. Sources only; native compilation and game integration are separate." -f $manifest.repositories.Count)
