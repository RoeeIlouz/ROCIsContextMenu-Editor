<#
.SYNOPSIS
    Builds the editor's brand assets (assets\*) from the ROCIs Apps brand kit.
.DESCRIPTION
    App icon: the studio "R" tile with its red dot replaced by a red context-menu card overlapping
    the R's leg (like Tasks' check and Schedule's grid). Also writes a small copy of the dark
    wordmark for the sidebar. Run after changing the brand kit; Compile.ps1 embeds assets\*.
#>
param([string]$BrandKit = (Join-Path $PSScriptRoot '..\..\..\ROCIsApps-Assets'))
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot '..\assets'
New-Item -ItemType Directory -Path $out -Force | Out-Null

$tile = [Drawing.Color]::FromArgb(0x2D, 0x2F, 0x33)
$red  = [Drawing.Color]::FromArgb(0xE5, 0x32, 0x3F)
$white = [Drawing.Color]::White

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = [Drawing.Drawing2D.GraphicsPath]::new()
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure(); return $p
}

# 1024 master
$src = [Drawing.Bitmap]::new((Join-Path $BrandKit 'Brand\studio-icon-1024.png'))
$bmp = [Drawing.Bitmap]::new(1024, 1024, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
$g.DrawImage($src, 0, 0, 1024, 1024)
$src.Dispose()

# Remove the studio red dot (top right): repaint any reddish pixel in that corner with the tile colour.
for ($y = 150; $y -lt 330; $y++) { for ($x = 720; $x -lt 920; $x++) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.A -gt 0 -and $c.R -gt $c.G + 25) { $bmp.SetPixel($x, $y, [Drawing.Color]::FromArgb($c.A, $tile.R, $tile.G, $tile.B)) }
} }

# Context menu card: tile-coloured outline separates it from the R, like the Tasks check.
$cx = 590; $cy = 600; $cw = 330; $ch = 300; $gap = 26
$outline = New-RoundedPath ($cx - $gap) ($cy - $gap) ($cw + 2 * $gap) ($ch + 2 * $gap) (48 + $gap)
$g.FillPath([Drawing.SolidBrush]::new($tile), $outline)
$card = New-RoundedPath $cx $cy $cw $ch 48
$g.FillPath([Drawing.SolidBrush]::new($red), $card)
# three menu items; the first is "highlighted" (full width), like a hovered menu entry
$pen = [Drawing.Pen]::new($white, 34); $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
foreach ($i in 0..2) {
    $yy = $cy + 78 + $i * 72
    $len = if ($i -eq 1) { $cw - 170 } else { $cw - 120 }
    $g.DrawLine($pen, $cx + 62, $yy, $cx + 62 + $len, $yy)
}
$g.Dispose()
$bmp.Save((Join-Path $out 'app-icon-1024.png'), [Drawing.Imaging.ImageFormat]::Png)

function Resize([Drawing.Bitmap]$b, [int]$size) {
    $r = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [Drawing.Graphics]::FromImage($r); $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'; $gg.SmoothingMode = 'AntiAlias'
    $gg.DrawImage($b, 0, 0, $size, $size); $gg.Dispose(); return $r
}
function PngBytes([Drawing.Bitmap]$b) { $ms = [IO.MemoryStream]::new(); $b.Save($ms, [Drawing.Imaging.ImageFormat]::Png); return , $ms.ToArray() }   # , keeps the byte[] whole

# .ico with PNG frames (Vista+): 16, 24, 32, 48, 64, 256
$sizes = 16, 24, 32, 48, 64, 256
$frames = [System.Collections.Generic.List[byte[]]]::new(); foreach ($s in $sizes) { $frames.Add((PngBytes (Resize $bmp $s))) }
$ms = [IO.MemoryStream]::new(); $bw = [IO.BinaryWriter]::new($ms)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $frames[$i].Length
    $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s })); $bw.Write([byte]$(if ($s -ge 256) { 0 } else { $s }))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$len); $bw.Write([uint32]$offset); $offset += $len
}
foreach ($f in $frames) { $bw.Write($f) }
$bw.Flush(); [IO.File]::WriteAllBytes((Join-Path $out 'app-icon.ico'), $ms.ToArray())
[IO.File]::WriteAllBytes((Join-Path $out 'app-icon-64.png'), (PngBytes (Resize $bmp 64)))
$bmp.Dispose()

# Sidebar signature: the official dark wordmark at 2x of its display size (~150 px wide)
$wm = [Drawing.Bitmap]::new((Join-Path $BrandKit 'Brand\wordmark-rocis-apps-dark.png'))
$w = 320; $h = [int]($wm.Height * $w / $wm.Width)
$small = [Drawing.Bitmap]::new($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gg = [Drawing.Graphics]::FromImage($small); $gg.InterpolationMode = 'HighQualityBicubic'; $gg.PixelOffsetMode = 'HighQuality'
$gg.DrawImage($wm, 0, 0, $w, $h); $gg.Dispose(); $wm.Dispose()
$small.Save((Join-Path $out 'wordmark.png'), [Drawing.Imaging.ImageFormat]::Png); $small.Dispose()

Get-ChildItem $out | ForEach-Object { '{0,-20} {1,7:N0} bytes' -f $_.Name, $_.Length }
