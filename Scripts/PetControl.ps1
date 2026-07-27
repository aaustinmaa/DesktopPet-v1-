param(
    [ValidateSet('idle','blink','happy','working','question','success','error','sleeping','reminder','waving','heart')]
    [string]$State = 'idle',
    [string]$Message = ''
)

$dataDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PixelHeartDesktopPet'
$commandPath = Join-Path $dataDirectory 'command.json'
New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null

[ordered]@{
    state = $State
    message = $Message
} | ConvertTo-Json | Set-Content -LiteralPath $commandPath -Encoding UTF8

Write-Host "Sent '$State' to Su Wudu Desktop Pet."
