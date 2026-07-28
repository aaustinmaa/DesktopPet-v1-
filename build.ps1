param(
    [ValidateSet('Debug','Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $projectRoot 'DesktopPet.csproj'
$frameworkMsBuild = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe'
$vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'

if (-not (Test-Path -LiteralPath $frameworkMsBuild)) {
    throw 'Windows .NET Framework MSBuild was not found.'
}
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Visual Studio Build Tools were not found. Install Visual Studio Build Tools with the .NET desktop build tools component.'
}

$visualStudioPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
if ([string]::IsNullOrWhiteSpace($visualStudioPath)) {
    throw 'Visual Studio Build Tools with MSBuild were not found.'
}

$roslynPath = Join-Path $visualStudioPath 'MSBuild\Current\Bin\Roslyn'
if (-not (Test-Path -LiteralPath (Join-Path $roslynPath 'csc.exe'))) {
    throw 'The Roslyn C# compiler was not found in Visual Studio Build Tools.'
}

& $frameworkMsBuild $projectPath /t:Rebuild /p:Configuration=$Configuration "/p:CscToolPath=$roslynPath" /p:CscToolExe=csc.exe /p:PlatformTarget=x64 /m /v:minimal
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}

$sourceOutput = Join-Path $projectRoot "bin\$Configuration"
$distOutput = Join-Path $projectRoot 'dist\SuWuDu'
if (Test-Path -LiteralPath $distOutput) {
    $resolvedProject = [System.IO.Path]::GetFullPath($projectRoot)
    $resolvedDist = [System.IO.Path]::GetFullPath($distOutput)
    if (-not $resolvedDist.StartsWith(
        $resolvedProject + [System.IO.Path]::DirectorySeparatorChar,
        [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean an output directory outside the project: $resolvedDist"
    }
    Remove-Item -LiteralPath $resolvedDist -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $distOutput | Out-Null
Copy-Item -Path (Join-Path $sourceOutput '*') -Destination $distOutput -Recurse -Force

Write-Host "Built successfully: $distOutput\SuWuDu.exe"
