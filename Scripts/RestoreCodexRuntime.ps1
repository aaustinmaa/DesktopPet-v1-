param(
    [switch]$NoDownload
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$packageDirectory = Join-Path $projectRoot 'Tools\Codex\package'
$manifestPath = Join-Path $packageDirectory 'codex-package.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Codex runtime manifest is missing: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$requiredFiles = @(
    [pscustomobject]@{
        RelativePath = 'bin\codex.exe'
        Hash = $manifest.requiredFiles.'bin/codex.exe'
    },
    [pscustomobject]@{
        RelativePath = 'bin\codex-code-mode-host.exe'
        Hash = $manifest.requiredFiles.'bin/codex-code-mode-host.exe'
    }
)

function Test-RuntimeFiles {
    foreach ($required in $requiredFiles) {
        $path = Join-Path $packageDirectory $required.RelativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $required.Hash) {
            throw "Codex runtime checksum mismatch: $path"
        }
    }
    return $true
}

if (Test-RuntimeFiles) {
    Write-Host "Codex runtime v$($manifest.version) is complete."
    return
}
if ($NoDownload) {
    throw 'The ignored Codex runtime binaries are missing. Run .\Scripts\RestoreCodexRuntime.ps1 while online.'
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'suwudu-codex-runtime-' + [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryDirectory 'codex-package.tar.gz'
$extractDirectory = Join-Path $temporaryDirectory 'extracted'
$releaseUrl = "https://github.com/openai/codex/releases/download/rust-v$($manifest.version)/codex-package-x86_64-pc-windows-msvc.tar.gz"
try {
    New-Item -ItemType Directory -Force -Path $extractDirectory | Out-Null
    Write-Host "Downloading official OpenAI Codex runtime v$($manifest.version)..."
    Invoke-WebRequest -Uri $releaseUrl -OutFile $archivePath -UseBasicParsing
    & tar.exe -xzf $archivePath -C $extractDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the Codex runtime archive.' }

    $binDirectory = Join-Path $packageDirectory 'bin'
    New-Item -ItemType Directory -Force -Path $binDirectory | Out-Null
    foreach ($required in $requiredFiles) {
        $fileName = Split-Path -Leaf $required.RelativePath
        $matches = @(Get-ChildItem -LiteralPath $extractDirectory -Recurse -File -Filter $fileName)
        if ($matches.Count -ne 1) {
            throw "Expected exactly one $fileName in the official runtime archive."
        }
        Copy-Item -LiteralPath $matches[0].FullName -Destination (Join-Path $binDirectory $fileName) -Force
    }

    if (-not (Test-RuntimeFiles)) {
        throw 'The downloaded Codex runtime is incomplete.'
    }
    Write-Host "Codex runtime v$($manifest.version) restored from OpenAI's GitHub Release."
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
