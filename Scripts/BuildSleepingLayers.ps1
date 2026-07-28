param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$spriteDirectory = Join-Path $ProjectRoot 'Assets\Sprites'
$sourcePath = Join-Path $spriteDirectory 'sleeping.png'
$basePath = Join-Path $spriteDirectory 'sleeping-base.png'
$zzzPath = Join-Path $spriteDirectory 'sleeping-zzz.png'

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
try {
    $base = $source.Clone(
        [System.Drawing.Rectangle]::new(
            0,
            0,
            $source.Width,
            $source.Height),
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $zzz = [System.Drawing.Bitmap]::new(
        $source.Width,
        $source.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $seeds = @(
            [System.Drawing.Point]::new(300, 10),
            [System.Drawing.Point]::new(270, 55)
        )

        foreach ($seed in $seeds) {
            $visited = [bool[]]::new($source.Width * $source.Height)
            $queue = [System.Collections.Generic.Queue[int]]::new()
            $seedIndex = $seed.Y * $source.Width + $seed.X
            $visited[$seedIndex] = $true
            $queue.Enqueue($seedIndex)

            while ($queue.Count -gt 0) {
                $index = $queue.Dequeue()
                $x = $index % $source.Width
                $y = [int][Math]::Floor($index / $source.Width)
                $pixel = $source.GetPixel($x, $y)
                $zzz.SetPixel($x, $y, $pixel)
                $base.SetPixel(
                    $x,
                    $y,
                    [System.Drawing.Color]::Transparent)

                for ($offsetY = -1; $offsetY -le 1; $offsetY++) {
                    for ($offsetX = -1; $offsetX -le 1; $offsetX++) {
                        if ($offsetX -eq 0 -and $offsetY -eq 0) {
                            continue
                        }
                        $nextX = $x + $offsetX
                        $nextY = $y + $offsetY
                        if ($nextX -lt 0 -or
                            $nextX -ge $source.Width -or
                            $nextY -lt 0 -or
                            $nextY -ge $source.Height) {
                            continue
                        }
                        $nextIndex = $nextY * $source.Width + $nextX
                        if ($visited[$nextIndex]) {
                            continue
                        }
                        $visited[$nextIndex] = $true
                        if ($source.GetPixel($nextX, $nextY).A -ge 12) {
                            $queue.Enqueue($nextIndex)
                        }
                    }
                }
            }
        }

        $smallZSource = $zzz.Clone(
            [System.Drawing.Rectangle]::new(268, 49, 26, 31),
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [System.Drawing.Graphics]::FromImage($zzz)
            try {
                $graphics.CompositingMode =
                    [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.InterpolationMode =
                    [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $graphics.PixelOffsetMode =
                    [System.Drawing.Drawing2D.PixelOffsetMode]::Half
                $graphics.SmoothingMode =
                    [System.Drawing.Drawing2D.SmoothingMode]::None
                $graphics.DrawImage(
                    $smallZSource,
                    [System.Drawing.Rectangle]::new(252, 72, 14, 17),
                    [System.Drawing.Rectangle]::new(
                        0,
                        0,
                        $smallZSource.Width,
                        $smallZSource.Height),
                    [System.Drawing.GraphicsUnit]::Pixel)
            }
            finally {
                $graphics.Dispose()
            }
        }
        finally {
            $smallZSource.Dispose()
        }

        $base.Save($basePath, [System.Drawing.Imaging.ImageFormat]::Png)
        $zzz.Save($zzzPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $base.Dispose()
        $zzz.Dispose()
    }
}
finally {
    $source.Dispose()
}

Write-Host "Sleeping layers created successfully."
