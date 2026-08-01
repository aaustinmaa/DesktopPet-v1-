param(
    [string]$Version,
    [string]$SourceDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $SourceDirectory = Join-Path $projectRoot 'dist\SuWuDu'
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$application = Join-Path $SourceDirectory 'SuWuDu.exe'
$updater = Join-Path $SourceDirectory 'SuWuDuUpdater.exe'
if (-not (Test-Path -LiteralPath $application -PathType Leaf)) {
    throw "Could not find the built application: $application"
}
if (-not (Test-Path -LiteralPath $updater -PathType Leaf)) {
    throw "Could not find the updater: $updater"
}

$fileVersion = [Version]([Diagnostics.FileVersionInfo]::GetVersionInfo($application).FileVersion)
$fileVersionText = $fileVersion.ToString(3)
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = $fileVersionText }
$Version = ([Version]$Version).ToString(3)
if ($Version -ne $fileVersionText) {
    throw "Requested release v$Version does not match SuWuDu.exe v$fileVersionText."
}

$outputDirectory = Join-Path $projectRoot 'dist\release-assets'
$stageDirectory = Join-Path $projectRoot 'dist\.update-stage'
$packageName = "SuWuDu-update-v$Version.zip"
$packagePath = Join-Path $outputDirectory $packageName
$checksumPath = $packagePath + '.sha256'

if (Test-Path -LiteralPath $stageDirectory) { Remove-Item -LiteralPath $stageDirectory -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Get-ChildItem -LiteralPath $SourceDirectory -Force |
    Where-Object { $_.Extension -ne '.pdb' -and $_.Name -ne 'Uninstall.exe' } |
    Copy-Item -Destination $stageDirectory -Recurse -Force

if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory(
    $stageDirectory, $packagePath,
    [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
[IO.File]::WriteAllText(
    $checksumPath,
    "$hash  $packageName`r`n",
    (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath $stageDirectory -Recurse -Force

Write-Host "Update package created: $packagePath"
Write-Host "Checksum created: $checksumPath"
