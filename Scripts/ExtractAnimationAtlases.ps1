param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$atlasDirectory = Join-Path $ProjectRoot 'Assets\Source\AnimationAtlases'
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

    $transparentPixel = [System.Drawing.Color]::FromArgb(0, 0, 0, 0)
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
            $Bitmap.SetPixel($x, $top, $transparentPixel)
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
                $transparentPixel)
        }
        $bottom--
    }

    $edgeBandHeight = [Math]::Min(8, [Math]::Floor($Bitmap.Height / 2))
    for ($y = 0; $y -lt $edgeBandHeight; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x, $y).A -gt 0) {
                $Bitmap.SetPixel($x, $y, $transparentPixel)
            }
            $bottomY = $Bitmap.Height - 1 - $y
            if ($Bitmap.GetPixel($x, $bottomY).A -gt 0) {
                $Bitmap.SetPixel($x, $bottomY, $transparentPixel)
            }
        }
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
        [switch]$ClearEdgeArtifacts,
        [switch]$PreserveAspectRatio,
        [double]$AspectScale = 1.0
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
                $destination = [System.Drawing.Rectangle]::new(0, 0, 362, 362)
                if ($PreserveAspectRatio) {
                    $scale = [Math]::Min(
                        362.0 / $cellImage.Width,
                        362.0 / $cellImage.Height)
                    $scale *= $AspectScale
                    $destinationWidth = [Math]::Max(
                        1,
                        [int][Math]::Round($cellImage.Width * $scale))
                    $destinationHeight = [Math]::Max(
                        1,
                        [int][Math]::Round($cellImage.Height * $scale))
                    $destination = [System.Drawing.Rectangle]::new(
                        [int][Math]::Round((362 - $destinationWidth) / 2.0),
                        [int][Math]::Round((362 - $destinationHeight) / 2.0),
                        $destinationWidth,
                        $destinationHeight)
                }

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
                        $destination,
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

function Build-IdleHandFrames {
    $basePath = Join-Path $spriteDirectory 'idle-v2-01.png'
    $baseFrame = [System.Drawing.Bitmap]::FromFile($basePath)
    try {
        $leftHand = [System.Drawing.Rectangle]::new(176, 270, 32, 35)
        $rightHand = [System.Drawing.Rectangle]::new(268, 270, 36, 35)
        $motions = @(
            [PSCustomObject]@{ LeftX = 0; LeftY = 0; RightX = 0; RightY = 0 },
            [PSCustomObject]@{ LeftX = 1; LeftY = -1; RightX = -1; RightY = -1 },
            [PSCustomObject]@{ LeftX = 2; LeftY = -2; RightX = -2; RightY = -2 },
            [PSCustomObject]@{ LeftX = 1; LeftY = -1; RightX = -1; RightY = -1 },
            [PSCustomObject]@{ LeftX = 0; LeftY = 0; RightX = 0; RightY = 0 },
            [PSCustomObject]@{ LeftX = -1; LeftY = 1; RightX = 1; RightY = 1 },
            [PSCustomObject]@{ LeftX = -2; LeftY = 2; RightX = 2; RightY = 2 },
            [PSCustomObject]@{ LeftX = -1; LeftY = 1; RightX = 1; RightY = 1 }
        )

        for ($frame = 1; $frame -le 8; $frame++) {
            $filename = 'idle-hands-v3-{0:D2}.png' -f $frame
            $path = Join-Path $spriteDirectory $filename
            $output = $baseFrame.Clone(
                [System.Drawing.Rectangle]::new(
                    0,
                    0,
                    $baseFrame.Width,
                    $baseFrame.Height),
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $motion = $motions[$frame - 1]
                if ($frame -ne 1 -and $frame -ne 5) {
                    $graphics = [System.Drawing.Graphics]::FromImage($output)
                    try {
                        $graphics.CompositingMode =
                            [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                        $graphics.FillRectangle(
                            [System.Drawing.Brushes]::Black,
                            $leftHand)
                        $graphics.FillRectangle(
                            [System.Drawing.Brushes]::Black,
                            $rightHand)
                        $graphics.DrawImage(
                            $baseFrame,
                            [System.Drawing.Rectangle]::new(
                                $leftHand.X + $motion.LeftX,
                                $leftHand.Y + $motion.LeftY,
                                $leftHand.Width,
                                $leftHand.Height),
                            $leftHand,
                            [System.Drawing.GraphicsUnit]::Pixel)
                        $graphics.DrawImage(
                            $baseFrame,
                            [System.Drawing.Rectangle]::new(
                                $rightHand.X + $motion.RightX,
                                $rightHand.Y + $motion.RightY,
                                $rightHand.Width,
                                $rightHand.Height),
                            $rightHand,
                            [System.Drawing.GraphicsUnit]::Pixel)
                    }
                    finally {
                        $graphics.Dispose()
                    }
                }

                $output.Save(
                    $path,
                    [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
            }
        }
    }
    finally {
        $baseFrame.Dispose()
    }
}

function Save-FixedGridFrames {
    param(
        [string]$AtlasPath,
        [int]$Count,
        [string]$Prefix
    )

    $atlas = [System.Drawing.Bitmap]::FromFile($AtlasPath)
    try {
        if ($atlas.Width -ne 1448 -or $atlas.Height -ne 1448) {
            throw "Expected a 1448x1448 fixed-grid atlas in $AtlasPath."
        }

        for ($frame = 0; $frame -lt $Count; $frame++) {
            $cell = Get-CellRectangle $atlas 4 4 $frame
            if ($cell.Width -ne 362 -or $cell.Height -ne 362) {
                throw "Expected 362x362 cells in $AtlasPath."
            }

            $output = $atlas.Clone(
                $cell,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            try {
                $filename = '{0}-{1:D2}.png' -f $Prefix, ($frame + 1)
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

function Align-IdleOpenCloseFrames {
    for ($frame = 1; $frame -le 16; $frame++) {
        $filename = 'idle-open-close-v5-{0:D2}.png' -f $frame
        $path = Join-Path $spriteDirectory $filename
        $input = [System.Drawing.Bitmap]::FromFile($path)
        try {
            $minimumX = $input.Width
            $minimumY = $input.Height
            for ($y = 0; $y -lt 240; $y++) {
                for ($x = 0; $x -lt $input.Width; $x++) {
                    if ($input.GetPixel($x, $y).A -lt 12) {
                        continue
                    }
                    if ($x -lt $minimumX) { $minimumX = $x }
                    if ($y -lt $minimumY) { $minimumY = $y }
                }
            }

            $offsetX = 25 - $minimumX
            $offsetY = 26 - $minimumY
            $output = New-TransparentBitmap $input.Width $input.Height
            try {
                $graphics = [System.Drawing.Graphics]::FromImage($output)
                try {
                    $graphics.CompositingMode =
                        [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $graphics.DrawImageUnscaled(
                        $input,
                        $offsetX,
                        $offsetY)
                }
                finally {
                    $graphics.Dispose()
                }

                $input.Dispose()
                $input = $null
                $output.Save(
                    $path,
                    [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
            }
        }
        finally {
            if ($null -ne $input) {
                $input.Dispose()
            }
        }
    }

    [System.IO.File]::Copy(
        (Join-Path $spriteDirectory 'idle-open-close-v5-01.png'),
        (Join-Path $spriteDirectory 'idle-open-close-v5-16.png'),
        $true)
}

function Lift-IdleOpenCloseHeart {
    $offsetsY = @(0, -2, -4, -6, -8, -10, -12, -14,
        -16, -14, -12, -10, -8, -6, -4, 0)
    $heartRegion = [System.Drawing.Rectangle]::new(160, 240, 140, 90)

    for ($frame = 1; $frame -le 16; $frame++) {
        $filename = 'idle-open-close-v5-{0:D2}.png' -f $frame
        $path = Join-Path $spriteDirectory $filename
        $input = [System.Drawing.Bitmap]::FromFile($path)
        try {
            $mask = [bool[]]::new(
                $heartRegion.Width * $heartRegion.Height)
            for ($localY = 0; $localY -lt $heartRegion.Height; $localY++) {
                for ($localX = 0; $localX -lt $heartRegion.Width; $localX++) {
                    $pixel = $input.GetPixel(
                        $heartRegion.X + $localX,
                        $heartRegion.Y + $localY)
                    $mask[$localY * $heartRegion.Width + $localX] =
                        $pixel.R -gt 150 -and
                        $pixel.G -lt 90 -and
                        $pixel.B -lt 90 -and
                        $pixel.A -gt 0
                }
            }

            $expandedMask = [bool[]]::new($mask.Length)
            for ($localY = 0; $localY -lt $heartRegion.Height; $localY++) {
                for ($localX = 0; $localX -lt $heartRegion.Width; $localX++) {
                    if (-not $mask[
                        $localY * $heartRegion.Width + $localX]) {
                        continue
                    }
                    for ($offsetY = -7; $offsetY -le 7; $offsetY++) {
                        for ($offsetX = -7; $offsetX -le 7; $offsetX++) {
                            $targetX = $localX + $offsetX
                            $targetY = $localY + $offsetY
                            if ($targetX -ge 0 -and
                                $targetX -lt $heartRegion.Width -and
                                $targetY -ge 0 -and
                                $targetY -lt $heartRegion.Height) {
                                $expandedMask[
                                    $targetY * $heartRegion.Width +
                                    $targetX] = $true
                            }
                        }
                    }
                }
            }

            $heartObjectMask = [bool[]]::new($mask.Length)
            for ($localY = 0; $localY -lt $heartRegion.Height; $localY++) {
                for ($localX = 0; $localX -lt $heartRegion.Width; $localX++) {
                    $index = $localY * $heartRegion.Width + $localX
                    if (-not $expandedMask[$index]) {
                        continue
                    }

                    $pixel = $input.GetPixel(
                        $heartRegion.X + $localX,
                        $heartRegion.Y + $localY)
                    $isDarkOutline = $pixel.A -gt 0 -and
                        $pixel.R -lt 120 -and
                        $pixel.G -lt 120 -and
                        $pixel.B -lt 120
                    $heartObjectMask[$index] =
                        $mask[$index] -or $isDarkOutline
                }
            }

            $output = $input.Clone(
                [System.Drawing.Rectangle]::new(
                    0,
                    0,
                    $input.Width,
                    $input.Height),
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $temporaryPath = "$path.tmp.png"
            try {
                for ($localY = 0;
                    $localY -lt $heartRegion.Height;
                    $localY++) {
                    for ($localX = 0;
                        $localX -lt $heartRegion.Width;
                        $localX++) {
                        if (-not $heartObjectMask[
                            $localY * $heartRegion.Width + $localX]) {
                            continue
                        }

                        $sourceX = $heartRegion.X + $localX
                        $sourceY = $heartRegion.Y + $localY
                        $output.SetPixel(
                            $sourceX,
                            $sourceY,
                            [System.Drawing.Color]::Black)
                    }
                }

                $heartOffsetY = $offsetsY[$frame - 1]
                for ($localY = 0;
                    $localY -lt $heartRegion.Height;
                    $localY++) {
                    for ($localX = 0;
                        $localX -lt $heartRegion.Width;
                        $localX++) {
                        if (-not $heartObjectMask[
                            $localY * $heartRegion.Width + $localX]) {
                            continue
                        }

                        $sourceX = $heartRegion.X + $localX
                        $sourceY = $heartRegion.Y + $localY
                        $targetY = $sourceY + $heartOffsetY
                        if ($targetY -ge 0 -and
                            $targetY -lt $output.Height) {
                            $output.SetPixel(
                                $sourceX,
                                $targetY,
                                $input.GetPixel($sourceX, $sourceY))
                        }
                    }
                }

                $input.Dispose()
                $input = $null
                $output.Save(
                    $temporaryPath,
                    [System.Drawing.Imaging.ImageFormat]::Png)
            }
            finally {
                $output.Dispose()
            }
        }
        finally {
            if ($null -ne $input) {
                $input.Dispose()
            }
        }
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    for ($frame = 1; $frame -le 16; $frame++) {
        $filename = 'idle-open-close-v5-{0:D2}.png' -f $frame
        $path = Join-Path $spriteDirectory $filename
        $temporaryPath = "$path.tmp.png"
        [System.IO.File]::Copy($temporaryPath, $path, $true)
        [System.IO.File]::Delete($temporaryPath)
    }
}

Save-CharacterFrames `
    (Join-Path $atlasDirectory 'idle-open-close-v5.png') `
    0 16 'idle-open-close-v5'
Align-IdleOpenCloseFrames
Lift-IdleOpenCloseHeart
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'idle-blink-v2.png') `
    8 8 'blink-v2' `
    -ClearEdgeArtifacts
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'social-v2.png') `
    0 8 'wave-v2'
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'heart-lift-v3.png') `
    0 8 'heart-lift-v3'
Save-FixedGridFrames `
    (Join-Path $atlasDirectory 'working-float-v3.png') `
    16 'working-float-v3'
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'idle-hit-v1.png') `
    0 16 'idle-hit-v1' `
    -ClearEdgeArtifacts
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'success-v2.png') `
    0 16 'success-v2' `
    -ClearEdgeArtifacts
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'error-v4.png') `
    0 16 'error-v4' `
    -ClearEdgeArtifacts `
    -PreserveAspectRatio `
    -AspectScale 1.07
Save-CharacterFrames `
    (Join-Path $atlasDirectory 'reminder-v2.png') `
    0 16 'reminder-v2' `
    -ClearEdgeArtifacts
Save-HammerFrames (Join-Path $atlasDirectory 'hammer-v2.png')

Write-Host 'Animation frames extracted successfully.'
