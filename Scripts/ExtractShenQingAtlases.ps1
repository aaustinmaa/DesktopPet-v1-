param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasDirectory = Join-Path $ProjectRoot 'Assets\Source\AnimationAtlases'
$spriteDirectory = Join-Path $ProjectRoot 'Assets\Sprites'

$ranges = @(
    @{ Atlas = 'shenqing-idle-blink-v1.png'; Start = 0; Count = 8; Prefix = 'shenqing-idle' },
    @{ Atlas = 'shenqing-idle-blink-v1.png'; Start = 8; Count = 8; Prefix = 'shenqing-blink' },
    @{ Atlas = 'shenqing-social-v1.png'; Start = 0; Count = 8; Prefix = 'shenqing-wave' },
    @{ Atlas = 'shenqing-social-v1.png'; Start = 8; Count = 8; Prefix = 'shenqing-heart' },
    @{ Atlas = 'shenqing-working-v1.png'; Start = 0; Count = 16; Prefix = 'shenqing-working' },
    @{ Atlas = 'shenqing-feedback-v1.png'; Start = 0; Count = 8; Prefix = 'shenqing-success' },
    @{ Atlas = 'shenqing-feedback-v1.png'; Start = 8; Count = 8; Prefix = 'shenqing-error' },
    @{ Atlas = 'shenqing-reminder-sleep-v1.png'; Start = 0; Count = 8; Prefix = 'shenqing-reminder' },
    @{ Atlas = 'shenqing-reminder-sleep-v1.png'; Start = 8; Count = 8; Prefix = 'shenqing-sleeping' }
)

foreach ($range in $ranges) {
    $atlasPath = Join-Path $atlasDirectory $range.Atlas
    $atlas = [System.Drawing.Bitmap]::FromFile($atlasPath)
    try {
        if ($atlas.Width -ne 1448 -or $atlas.Height -ne 1448) {
            throw "Expected a 1448x1448 fixed-grid atlas in $atlasPath."
        }

        for ($frame = 0; $frame -lt $range.Count; $frame++) {
            $atlasIndex = $range.Start + $frame
            $column = $atlasIndex % 4
            $row = [Math]::Floor($atlasIndex / 4)
            $cell = [System.Drawing.Rectangle]::new(
                $column * 362,
                $row * 362,
                362,
                362)
            $output = $atlas.Clone(
                $cell,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $filename = '{0}-{1:D2}.png' -f `
                    $range.Prefix, ($frame + 1)
                $output.Save(
                    (Join-Path $spriteDirectory $filename),
                    [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
            }
        }
    }
    finally {
        $atlas.Dispose()
    }
}

Write-Host 'Shen Qing animation frames extracted successfully.'
