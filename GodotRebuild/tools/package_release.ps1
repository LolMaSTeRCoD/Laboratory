param(
    [string]$Executable,
    [string]$Destination
)
$ErrorActionPreference = 'Stop'
$Project = [System.IO.Path]::GetDirectoryName($PSScriptRoot)
$RepositoryRoot = [System.IO.Path]::GetDirectoryName($Project)
if ([string]::IsNullOrWhiteSpace($Executable)) { $Executable = Join-Path $RepositoryRoot 'KDTD.exe' }
if ([string]::IsNullOrWhiteSpace($Destination)) { $Destination = Join-Path $Project 'Builds\Release\KDTD-Windows.zip' }
$Executable = [System.IO.Path]::GetFullPath($Executable)
$Destination = [System.IO.Path]::GetFullPath($Destination)
$StagedArchive = $Destination + '.new'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'KDTD.exe was not found.' }
New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($Destination)) -Force | Out-Null
$packageLock = [System.IO.File]::Open(($Destination+'.lock'),[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
$sourceSnapshot = $null
try {
# Prevent modification/replacement of the input until compression and metadata
# are complete. Hashes, length and version describe this same readable snapshot.
$sourceSnapshot = [System.IO.File]::Open($Executable,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
$snapshotLength = $sourceSnapshot.Length
$snapshotVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Executable).FileVersion
$snapshotSha = [System.Security.Cryptography.SHA256]::Create()
try { $snapshotHash = [System.Convert]::ToHexString($snapshotSha.ComputeHash($sourceSnapshot)) } finally { $snapshotSha.Dispose() }
$readme = @'
КОДИ TD — Made by Alex

Распакуйте архив в отдельную папку и запустите KDTD.exe.
Редактор, Blender, исходники и интернет для запуска не нужны.
Все игровые модели, карты, текстуры и основные звуки встроены в EXE.

ЛКМ по карточке — выбрать башню; ЛКМ по свободной траве — построить.
ЛКМ по башне — характеристики, улучшение и продажа; ЛКМ по врагу — его здоровье и броня.
ПКМ или Escape — отменить строительство; ПКМ с перетаскиванием — камера.
Колесо — приблизить к курсору. Средняя кнопка — вращать камеру; Home — общий вид.
Space — следующая волна; P — пауза; F11 — полный экран; Escape — меню.
После завершения арены переход открывает отдельную фазу строительства.
Первая волна новой арены запускается следующим нажатием Space или кнопки волны.
На новую арену переносится 10% оставшегося золота плюс стартовые 220 монет.
Меню содержит ограничение FPS: 30, 60 (по умолчанию), 120 или без ограничения.
Музыка и эффекты регулируются независимо в верхней панели.

Для своего плейлиста создайте папку Music рядом с KDTD.exe и добавьте MP3/OGG/WAV.
Без неё используется встроенная композиция. Список проигрывается по кругу.
Настройки сохраняются в профиле Windows, а не в папке игры.
'@
$stream = [System.IO.File]::Open($StagedArchive,[System.IO.FileMode]::Create)
$archive = [System.IO.Compression.ZipArchive]::new($stream,[System.IO.Compression.ZipArchiveMode]::Create)
try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$Executable,'KDTD.exe',[System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    $entry = $archive.CreateEntry('README.txt')
    $writer = [System.IO.StreamWriter]::new($entry.Open(),[System.Text.UTF8Encoding]::new($true))
    try { $writer.Write($readme) } finally { $writer.Dispose() }
} finally { $archive.Dispose(); $stream.Dispose() }
$check = [System.IO.Compression.ZipFile]::OpenRead($StagedArchive)
try {
    if ($check.Entries.Count -ne 2 -or $null -eq $check.GetEntry('KDTD.exe')) { throw 'Unexpected release archive contents.' }
    if ($check.GetEntry('KDTD.exe').Length -ne $snapshotLength) { throw 'Executable length in ZIP does not match.' }
    $entryStream = $check.GetEntry('KDTD.exe').Open()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $entryHash = [System.Convert]::ToHexString($sha.ComputeHash($entryStream)) } finally { $sha.Dispose(); $entryStream.Dispose() }
    if ($entryHash -ne $snapshotHash) { throw 'ZIP executable SHA256 does not match the verified build.' }
} finally { $check.Dispose() }
$metadata = @{
    version = $snapshotVersion
    packaged_at = (Get-Date).ToString('o')
    executable = $Executable
    executable_bytes = $snapshotLength
    executable_sha256 = $snapshotHash
    archive = $Destination
    archive_bytes = (Get-Item -LiteralPath $StagedArchive).Length
    archive_sha256 = (Get-FileHash -LiteralPath $StagedArchive -Algorithm SHA256).Hash
    contents = @('KDTD.exe','README.txt')
} | ConvertTo-Json
$readmePath = Join-Path ([System.IO.Path]::GetDirectoryName($Destination)) 'README.txt'
[System.IO.File]::WriteAllText(($readmePath+'.new'),$readme,[System.Text.UTF8Encoding]::new($true))
[System.IO.File]::WriteAllText(($Destination+'.json.new'),$metadata,[System.Text.UTF8Encoding]::new($true))
# Every output is complete before the public archive is replaced. Each rename
# is atomic; this is not a cross-file transaction. Consumers can verify the
# sidecar against archive_sha256. The EXE snapshot stays locked throughout.
[System.IO.File]::Move($StagedArchive,$Destination,$true)
[System.IO.File]::Move(($readmePath+'.new'),$readmePath,$true)
[System.IO.File]::Move(($Destination+'.json.new'),($Destination+'.json'),$true)
Write-Output "RELEASE_PACKAGE_OK: $Destination"
} finally {
    if ($null -ne $sourceSnapshot) { $sourceSnapshot.Dispose() }
    $packageLock.Dispose()
}
