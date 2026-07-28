param(
    [string]$SourceDirectory,
    [switch]$KeepBuildFiles
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$frameworkDirectory = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $frameworkDirectory 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $csc)) { throw 'Could not find the .NET Framework C# compiler (csc.exe).' }

if ([string]::IsNullOrWhiteSpace($SourceDirectory)) {
    $candidate = Join-Path $projectRoot 'dist\SuWuDu'
    if (-not (Test-Path -LiteralPath $candidate)) { $candidate = Join-Path $projectRoot 'dist\DesktopPet' }
    $SourceDirectory = $candidate
}
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Could not find the application directory: $SourceDirectory. Publish the app to dist\SuWuDu first."
}

$appSource = Join-Path $SourceDirectory 'SuWuDu.exe'
if (-not (Test-Path -LiteralPath $appSource)) { $appSource = Join-Path $SourceDirectory 'DesktopPet.exe' }
if (-not (Test-Path -LiteralPath $appSource)) { throw "The source directory does not contain SuWuDu.exe or DesktopPet.exe: $SourceDirectory" }

$buildRoot = Join-Path $projectRoot 'Installer\build'
$stageDirectory = Join-Path $buildRoot 'payload'
$stub = Join-Path $buildRoot 'SuWuDuInstallerStub.exe'
$uninstaller = Join-Path $stageDirectory 'Uninstall.exe'
$zipPath = Join-Path $buildRoot 'payload.zip'
$outputDirectory = Join-Path $projectRoot 'dist'
$installerFileName = ([char]0x82CF).ToString() + ([char]0x65E0).ToString() + ([char]0x5EA6).ToString() +
    ([char]0x5B89).ToString() + ([char]0x88C5).ToString() + ([char]0x7A0B).ToString() + ([char]0x5E8F).ToString() + '.exe'
$output = Join-Path $outputDirectory $installerFileName

if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Get-ChildItem -LiteralPath $SourceDirectory -Force | Copy-Item -Destination $stageDirectory -Recurse -Force
if (-not (Test-Path -LiteralPath (Join-Path $stageDirectory 'SuWuDu.exe'))) {
    Move-Item -LiteralPath (Join-Path $stageDirectory 'DesktopPet.exe') -Destination (Join-Path $stageDirectory 'SuWuDu.exe')
    $oldConfig = Join-Path $stageDirectory 'DesktopPet.exe.config'
    if (Test-Path -LiteralPath $oldConfig) { Move-Item -LiteralPath $oldConfig -Destination (Join-Path $stageDirectory 'SuWuDu.exe.config') }
    $oldPdb = Join-Path $stageDirectory 'DesktopPet.pdb'
    if (Test-Path -LiteralPath $oldPdb) { Move-Item -LiteralPath $oldPdb -Destination (Join-Path $stageDirectory 'SuWuDu.pdb') }
}

$references = @(
    '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll', '/r:System.Windows.Forms.dll',
    '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll', '/r:Microsoft.CSharp.dll'
)
$installerSource = Join-Path $projectRoot 'Installer\SuWuDuInstaller.cs'
$uninstallerSource = Join-Path $projectRoot 'Installer\SuWuDuUninstaller.cs'
$icon = Join-Path $projectRoot 'Assets\app.ico'
$iconArgument = if (Test-Path -LiteralPath $icon) { "/win32icon:$icon" } else { $null }

& $csc /nologo /codepage:65001 /target:winexe /optimize+ "/out:$stub" $references $iconArgument $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
& $csc /nologo /codepage:65001 /target:winexe /optimize+ "/out:$uninstaller" $references $iconArgument $uninstallerSource
if ($LASTEXITCODE -ne 0) { throw 'Uninstaller compilation failed.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stageDirectory, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$magic = [Text.Encoding]::ASCII.GetBytes('SWDPACK1')
$payloadLength = (Get-Item -LiteralPath $zipPath).Length
$destinationStream = [IO.File]::Open($output, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $stubStream = [IO.File]::OpenRead($stub)
    try { $stubStream.CopyTo($destinationStream) } finally { $stubStream.Dispose() }
    $payloadStream = [IO.File]::OpenRead($zipPath)
    try { $payloadStream.CopyTo($destinationStream) } finally { $payloadStream.Dispose() }
    $destinationStream.Write($magic, 0, $magic.Length)
    $lengthBytes = [BitConverter]::GetBytes([Int64]$payloadLength)
    $destinationStream.Write($lengthBytes, 0, $lengthBytes.Length)
}
finally { $destinationStream.Dispose() }

if (-not $KeepBuildFiles) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
Write-Host "Installer created: $output"
