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
$assetRoot = Join-Path $projectRoot 'Assets'
$assetClassificationPath = Join-Path $assetRoot 'asset-classification.json'
$sourceAssetRoot = Join-Path $SourceDirectory 'Assets'
$setupManifest = Join-Path $projectRoot 'Installer\SuWuDuSetup.manifest'
$installerFileName = ([char]0x82CF).ToString() + ([char]0x65E0).ToString() + ([char]0x5EA6).ToString() +
    ([char]0x5B89).ToString() + ([char]0x88C5).ToString() + ([char]0x7A0B).ToString() + ([char]0x5E8F).ToString() + '.exe'
$output = Join-Path $outputDirectory $installerFileName

if (-not (Test-Path -LiteralPath $assetClassificationPath -PathType Leaf)) {
    throw "Asset classification file is missing: $assetClassificationPath"
}
if (-not (Test-Path -LiteralPath $setupManifest -PathType Leaf)) {
    throw "Installer application manifest is missing: $setupManifest"
}

$assetClassification = Get-Content -LiteralPath $assetClassificationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$usedPatterns = @($assetClassification.used)
$unusedPatterns = @($assetClassification.unused)
if ($usedPatterns.Count -eq 0 -or $unusedPatterns.Count -eq 0) {
    throw 'Asset classification must define non-empty used and unused pattern lists.'
}

$classifiedAssets = @{}
$usedAssetPaths = New-Object System.Collections.Generic.List[string]
$unusedAssetPaths = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $assetRoot -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring($assetRoot.Length).TrimStart('\')
    $usedMatches = @($usedPatterns | Where-Object { $relativePath -like $_ })
    $unusedMatches = @($unusedPatterns | Where-Object { $relativePath -like $_ })
    $matchCount = $usedMatches.Count + $unusedMatches.Count
    if ($matchCount -ne 1) {
        throw "Asset must match exactly one used/unused classification: $relativePath (matches: $matchCount)"
    }

    if ($usedMatches.Count -eq 1) {
        $usedAssetPaths.Add($relativePath)
        $classifiedAssets[$relativePath.ToLowerInvariant()] = 'used'
    }
    else {
        $unusedAssetPaths.Add($relativePath)
        $classifiedAssets[$relativePath.ToLowerInvariant()] = 'unused'
    }
}

if (-not (Test-Path -LiteralPath $sourceAssetRoot -PathType Container)) {
    throw "The development output is missing its Assets directory: $sourceAssetRoot"
}

$sourceAssetPaths = @(
    Get-ChildItem -LiteralPath $sourceAssetRoot -Recurse -File | ForEach-Object {
        $_.FullName.Substring($sourceAssetRoot.Length).TrimStart('\')
    }
)
$unexpectedSourceAssets = @($sourceAssetPaths | Where-Object {
    -not $classifiedAssets.ContainsKey($_.ToLowerInvariant()) -or
    $classifiedAssets[$_.ToLowerInvariant()] -ne 'used'
})
if ($unexpectedSourceAssets.Count -gt 0) {
    throw "Development output contains unused or unclassified assets:`r`n$($unexpectedSourceAssets -join "`r`n")"
}

$missingUsedAssets = @($usedAssetPaths | Where-Object { $_ -notin $sourceAssetPaths })
if ($missingUsedAssets.Count -gt 0) {
    throw "Development output is missing used assets:`r`n$($missingUsedAssets -join "`r`n")"
}

Write-Host "Asset classification verified: $($usedAssetPaths.Count) used, $($unusedAssetPaths.Count) unused."

if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Get-ChildItem -LiteralPath $SourceDirectory -Force |
    Where-Object { $_.Name -ne 'Assets' } |
    Copy-Item -Destination $stageDirectory -Recurse -Force
$stageAssetRoot = Join-Path $stageDirectory 'Assets'
New-Item -ItemType Directory -Force -Path $stageAssetRoot | Out-Null
foreach ($relativePath in $usedAssetPaths) {
    $sourcePath = Join-Path $sourceAssetRoot $relativePath
    $destinationPath = Join-Path $stageAssetRoot $relativePath
    $destinationParent = Split-Path -Parent $destinationPath
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}
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

& $csc /nologo /codepage:65001 /target:winexe /optimize+ "/win32manifest:$setupManifest" "/out:$stub" $references $iconArgument $installerSource
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
& $csc /nologo /codepage:65001 /target:winexe /optimize+ "/win32manifest:$setupManifest" "/out:$uninstaller" $references $iconArgument $uninstallerSource
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
