param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$parsedVersion = [Version]$Version.TrimStart('v', 'V')
$Version = $parsedVersion.ToString(3)
$assemblyVersion = "$Version.0"
$assemblyInfoPath = Join-Path $projectRoot 'Properties\AssemblyInfo.cs'
$readmePath = Join-Path $projectRoot 'README.md'

$assemblyInfo = [IO.File]::ReadAllText($assemblyInfoPath)
$assemblyInfo = [Text.RegularExpressions.Regex]::Replace(
    $assemblyInfo,
    'AssemblyVersion\("[0-9.]+"\)',
    "AssemblyVersion(`"$assemblyVersion`")")
$assemblyInfo = [Text.RegularExpressions.Regex]::Replace(
    $assemblyInfo,
    'AssemblyFileVersion\("[0-9.]+"\)',
    "AssemblyFileVersion(`"$assemblyVersion`")")
[IO.File]::WriteAllText($assemblyInfoPath, $assemblyInfo, (New-Object Text.UTF8Encoding($false)))

if (Test-Path -LiteralPath $readmePath) {
    $readme = [IO.File]::ReadAllText($readmePath)
    $readme = [Text.RegularExpressions.Regex]::Replace(
        $readme,
        '项目当前版本为 `[^`]+`',
        "项目当前版本为 ``$Version``")
    [IO.File]::WriteAllText($readmePath, $readme, (New-Object Text.UTF8Encoding($false)))
}

& (Join-Path $projectRoot 'build.ps1') -Configuration Release
if ($LASTEXITCODE -ne 0) { throw 'Application build failed.' }
& (Join-Path $projectRoot 'build-update.ps1') -Version $Version
if ($LASTEXITCODE -ne 0) { throw 'Update package build failed.' }
& (Join-Path $projectRoot 'build-installer.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }

Write-Host "Release v$Version is ready under dist."
