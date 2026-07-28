param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasDirectory = Join-Path $ProjectRoot 'Assets\Source\AnimationAtlases'
$spriteDirectory = Join-Path $ProjectRoot 'Assets\Sprites'
$masterPath = Join-Path $atlasDirectory 'working-float-v3-master.png'
$atlasPath = Join-Path $atlasDirectory 'working-float-v3.png'
$sourceAtlasPath = Join-Path $atlasDirectory 'working-float-v3-source.png'
$frameSize = 362
$columns = 4
$rows = 4
$offsetsY = @(0, 0, 0, 0, -1, -1, -1, -1,
    -2, -2, -2, -2, -3, -3, -3, -3)

function New-TransparentBitmap {
    param(
        [int]$Width,
        [int]$Height
    )

    return [System.Drawing.Bitmap]::new(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

function Copy-Bitmap {
    param([System.Drawing.Bitmap]$Bitmap)

    return $Bitmap.Clone(
        [System.Drawing.Rectangle]::new(
            0,
            0,
            $Bitmap.Width,
            $Bitmap.Height),
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}

$master = [System.Drawing.Bitmap]::FromFile($masterPath)
$maskPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
$maskPath.FillMode = [System.Drawing.Drawing2D.FillMode]::Winding
$maskRegion = $null
$baseFrame = $null
$atlas = $null
$sourceAtlas = $null
try {
    if ($master.Width -ne $frameSize -or $master.Height -ne $frameSize) {
        throw "Expected a ${frameSize}x${frameSize} master image."
    }

    $screenPoints = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(207, 232),
        [System.Drawing.Point]::new(331, 240),
        [System.Drawing.Point]::new(340, 318),
        [System.Drawing.Point]::new(194, 318)
    )
    $basePoints = [System.Drawing.Point[]]@(
        [System.Drawing.Point]::new(130, 305),
        [System.Drawing.Point]::new(345, 305),
        [System.Drawing.Point]::new(345, 344),
        [System.Drawing.Point]::new(130, 344)
    )
    $maskPath.AddPolygon($screenPoints)
    $maskPath.AddPolygon($basePoints)
    $maskRegion = [System.Drawing.Region]::new($maskPath)

    $baseFrame = Copy-Bitmap $master
    for ($y = 0; $y -lt $frameSize; $y++) {
        for ($x = 0; $x -lt $frameSize; $x++) {
            if ($maskRegion.IsVisible($x, $y) -and
                $master.GetPixel($x, $y).A -gt 0) {
                $baseFrame.SetPixel(
                    $x,
                    $y,
                    [System.Drawing.Color]::Transparent)
            }
        }
    }

    $atlasWidth = $frameSize * $columns
    $atlasHeight = $frameSize * $rows
    $atlas = New-TransparentBitmap $atlasWidth $atlasHeight
    $sourceAtlas = New-TransparentBitmap $atlasWidth $atlasHeight
    $sourceGraphics = [System.Drawing.Graphics]::FromImage($sourceAtlas)
    try {
        $sourceGraphics.Clear([System.Drawing.Color]::FromArgb(
            255,
            255,
            0,
            255))
    }
    finally {
        $sourceGraphics.Dispose()
    }

    for ($index = 0; $index -lt $offsetsY.Count; $index++) {
        $frame = Copy-Bitmap $baseFrame
        try {
            $offsetY = $offsetsY[$index]
            for ($y = 0; $y -lt $frameSize; $y++) {
                for ($x = 0; $x -lt $frameSize; $x++) {
                    if (-not $maskRegion.IsVisible($x, $y)) {
                        continue
                    }

                    $pixel = $master.GetPixel($x, $y)
                    if ($pixel.A -eq 0) {
                        continue
                    }

                    $targetY = $y + $offsetY
                    if ($targetY -ge 0 -and $targetY -lt $frameSize) {
                        $frame.SetPixel($x, $targetY, $pixel)
                    }
                }
            }

            $column = $index % $columns
            $row = [Math]::Floor($index / $columns)
            $targetX = $column * $frameSize
            $targetY = $row * $frameSize

            $graphics = [System.Drawing.Graphics]::FromImage($atlas)
            try {
                $graphics.CompositingMode =
                    [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.DrawImageUnscaled($frame, $targetX, $targetY)
            }
            finally {
                $graphics.Dispose()
            }

            $sourceGraphics =
                [System.Drawing.Graphics]::FromImage($sourceAtlas)
            try {
                $sourceGraphics.CompositingMode =
                    [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                $sourceGraphics.DrawImageUnscaled($frame, $targetX, $targetY)
            }
            finally {
                $sourceGraphics.Dispose()
            }

            $frameFilename =
                'working-float-v3-{0:D2}.png' -f ($index + 1)
            $frame.Save(
                (Join-Path $spriteDirectory $frameFilename),
                [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $frame.Dispose()
        }
    }

    $atlas.Save(
        $atlasPath,
        [System.Drawing.Imaging.ImageFormat]::Png)
    $sourceAtlas.Save(
        $sourceAtlasPath,
        [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    if ($null -ne $sourceAtlas) { $sourceAtlas.Dispose() }
    if ($null -ne $atlas) { $atlas.Dispose() }
    if ($null -ne $baseFrame) { $baseFrame.Dispose() }
    if ($null -ne $maskRegion) { $maskRegion.Dispose() }
    $maskPath.Dispose()
    $master.Dispose()
}

Write-Host 'Stable working atlas generated successfully.'
