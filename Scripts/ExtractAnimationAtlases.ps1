param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasDirectory = Join-Path $ProjectRoot 'Assets\AnimationAtlases'
$spriteDirectory = Join-Path $ProjectRoot 'Assets\Sprites'

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

function Clear-HorizontalEdgeArtifacts {
    param(
        [System.Drawing.Bitmap]$Bitmap
    )

    $top = 0
    while ($top -lt $Bitmap.Height) {
        $hasVisiblePixel = $false
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x, $top).A -ge 12) {
                $hasVisiblePixel = $true
                break
            }
        }
        if (-not $hasVisiblePixel) {
            break
        }
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $Bitmap.SetPixel($x, $top, [System.Drawing.Color]::Transparent)
        }
        $top++
    }

    $bottom = $Bitmap.Height - 1
    while ($bottom -ge 0) {
        $hasVisiblePixel = $false
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x, $bottom).A -ge 12) {
                $hasVisiblePixel = $true
                break
            }
        }
        if (-not $hasVisiblePixel) {
            break
        }
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            $Bitmap.SetPixel(
                $x,
                $bottom,
                [System.Drawing.Color]::Transparent)
        }
        $bottom--
    }
}

function Get-CellRectangle {
    param(
        [System.Drawing.Image]$Image,
        [int]$Columns,
        [int]$Rows,
        [int]$Index
    )

    $column = $Index % $Columns
    $row = [Math]::Floor($Index / $Columns)
    $left = [int][Math]::Round($column * $Image.Width / $Columns)
    $right = [int][Math]::Round(($column + 1) * $Image.Width / $Columns)
    $top = [int][Math]::Round($row * $Image.Height / $Rows)
    $bottom = [int][Math]::Round(($row + 1) * $Image.Height / $Rows)
    return [System.Drawing.Rectangle]::new(
        $left,
        $top,
        ($right - $left),
        ($bottom - $top))
}

function Get-ContentBands {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [ValidateSet('Horizontal', 'Vertical')]
        [string]$Axis
    )

    $limit = if ($Axis -eq 'Horizontal') {
        $Bitmap.Width
    }
    else {
        $Bitmap.Height
    }
    $crossLimit = if ($Axis -eq 'Horizontal') {
        $Bitmap.Height
    }
    else {
        $Bitmap.Width
    }

    $bands = @()
    $insideBand = $false
    $start = 0
    for ($position = 0; $position -lt $limit; $position++) {
        $hasVisiblePixel = $false
        for ($cross = 0; $cross -lt $crossLimit; $cross++) {
            $pixel = if ($Axis -eq 'Horizontal') {
                $Bitmap.GetPixel($position, $cross)
            }
            else {
                $Bitmap.GetPixel($cross, $position)
            }
            if ($pixel.A -ge 12) {
                $hasVisiblePixel = $true
                break
            }
        }

        if ($hasVisiblePixel -and -not $insideBand) {
            $start = $position
            $insideBand = $true
        }
        elseif (-not $hasVisiblePixel -and $insideBand) {
            $bands += [PSCustomObject]@{
                Start = $start
                End = $position - 1
            }
            $insideBand = $false
        }
    }

    if ($insideBand) {
        $bands += [PSCustomObject]@{
            Start = $start
            End = $limit - 1
        }
    }
    return $bands
}

function Save-CharacterFrames {
    param(
        [string]$AtlasPath,
        [int]$StartIndex,
        [int]$Count,
        [string]$Prefix,
        [switch]$ClearEdgeArtifacts
    )

    $atlas = [System.Drawing.Bitmap]::FromFile($AtlasPath)
    try {
        $columnBands = @(Get-ContentBands $atlas 'Horizontal')
        $rowBands = @(Get-ContentBands $atlas 'Vertical')
        if ($columnBands.Count -ne 4 -or $rowBands.Count -ne 4) {
            throw "Expected a 4x4 content grid in $AtlasPath."
        }

        $maximumBandWidth = ($columnBands |
            ForEach-Object { $_.End - $_.Start + 1 } |
            Measure-Object -Maximum).Maximum
        $maximumBandHeight = ($rowBands |
            ForEach-Object { $_.End - $_.Start + 1 } |
            Measure-Object -Maximum).Maximum
        $cropWidth = [int]$maximumBandWidth + 40
        $cropHeight = [int]$maximumBandHeight + 40

        for ($frame = 0; $frame -lt $Count; $frame++) {
            $atlasIndex = $StartIndex + $frame
            $column = $atlasIndex % 4
            $row = [Math]::Floor($atlasIndex / 4)
            $centerX = ($columnBands[$column].Start +
                $columnBands[$column].End) / 2.0
            $centerY = ($rowBands[$row].Start +
                $rowBands[$row].End) / 2.0
            $left = [int][Math]::Round($centerX - $cropWidth / 2.0)
            $top = [int][Math]::Round($centerY - $cropHeight / 2.0)
            $left = [Math]::Max(0,
                [Math]::Min($left, $atlas.Width - $cropWidth))
            $top = [Math]::Max(0,
                [Math]::Min($top, $atlas.Height - $cropHeight))
            $cell = [System.Drawing.Rectangle]::new(
                $left,
                $top,
                $cropWidth,
                $cropHeight)
            $cellImage = $atlas.Clone(
                $cell,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $output = New-TransparentBitmap 362 362
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($output)
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
                        $cellImage,
                        ([System.Drawing.Rectangle]::new(0, 0, 362, 362)),
                        ([System.Drawing.Rectangle]::new(
                            0,
                            0,
                            $cellImage.Width,
                            $cellImage.Height)),
                        [System.Drawing.GraphicsUnit]::Pixel)
                }
                finally {
                    $graphics.Dispose()
                }

                if ($ClearEdgeArtifacts) {
                    Clear-HorizontalEdgeArtifacts $output
                }

                $filename = '{0}-{1:D2}.png' -f $Prefix, ($frame + 1)
                $output.Save(
                    (Join-Path $spriteDirectory $filename),
                    [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
                $cellImage.Dispose()
            }
        }
    }
    finally {
        $atlas.Dispose()
    }
}

function Get-AlphaBounds {
    param([System.Drawing.Bitmap]$Bitmap)

    $minimumX = $Bitmap.Width
    $minimumY = $Bitmap.Height
    $maximumX = -1
    $maximumY = -1

    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x, $y).A -lt 12) {
                continue
            }
            if ($x -lt $minimumX) { $minimumX = $x }
            if ($x -gt $maximumX) { $maximumX = $x }
            if ($y -lt $minimumY) { $minimumY = $y }
            if ($y -gt $maximumY) { $maximumY = $y }
        }
    }

    if ($maximumX -lt 0) {
        return $null
    }

    return [System.Drawing.Rectangle]::new(
        $minimumX,
        $minimumY,
        ($maximumX - $minimumX + 1),
        ($maximumY - $minimumY + 1))
}

function Save-HammerFrames {
    param([string]$AtlasPath)

    $atlas = [System.Drawing.Bitmap]::FromFile($AtlasPath)
    try {
        for ($frame = 0; $frame -lt 9; $frame++) {
            $cellRectangle = Get-CellRectangle $atlas 3 3 $frame
            $cell = $atlas.Clone(
                $cellRectangle,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $output = New-TransparentBitmap 180 180
                try {
                    $bounds = Get-AlphaBounds $cell
                    if ($null -ne $bounds) {
                        $scale = [Math]::Min(
                            150.0 / $bounds.Width,
                            150.0 / $bounds.Height)
                        $width = [Math]::Max(
                            1,
                            [int][Math]::Round($bounds.Width * $scale))
                        $height = [Math]::Max(
                            1,
                            [int][Math]::Round($bounds.Height * $scale))
                        $destination = [System.Drawing.Rectangle]::new(
                            [int][Math]::Round((180 - $width) / 2.0),
                            [int][Math]::Round((180 - $height) / 2.0),
                            $width,
                            $height)

                        $graphics = [System.Drawing.Graphics]::FromImage($output)
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
                                $cell,
                                $destination,
                                $bounds,
                                [System.Drawing.GraphicsUnit]::Pixel)
                        }
                        finally {
                            $graphics.Dispose()
                        }
                    }

                    $filename = 'hammer-v2-{0:D2}.png' -f ($frame + 1)
                    $output.Save(
                        (Join-Path $spriteDirectory $filename),
                        [System.Drawing.Imaging.ImageFormat]::Png)
                }
                finally {
                    $output.Dispose()
                }
            }
            finally {
                $cell.Dispose()
            }
        }
    }
    finally {
        $atlas.Dispose()
    }
}

Save-CharacterFrames `
    (Join-Path $atlasDirectory 'idle-blink-v2.png') `
    0 8 'idle-v2'
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'idle-blink-v2.png') `
    8 8 'blink-v2' `
    -ClearEdgeArtifacts
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'social-v2.png') `
    0 8 'wave-v2'
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'social-v2.png') `
    8 8 'heart-v2'
Save-HammerFrames (Join-Path $atlasDirectory 'hammer-v2.png')

Write-Host 'Animation frames extracted successfully.'
