param(
    [string]$OutDir = (Join-Path $PSScriptRoot "icons_png")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function New-Color([int]$r, [int]$g, [int]$b, [int]$a = 255) {
    return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function New-Point([float]$x, [float]$y) {
    return [System.Drawing.PointF]::new($x, $y)
}

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $d = $r * 2
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-BadgeBase([System.Drawing.Graphics]$g, [System.Drawing.Color]$borderColor) {
    $path = New-RoundedRectPath 14 14 228 228 44
    $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        (New-Point 14 14),
        (New-Point 242 242),
        (New-Color 30 33 56),
        (New-Color 18 20 36)
    )
    $g.FillPath($bgBrush, $path)
    $pen = [System.Drawing.Pen]::new($borderColor, 8)
    $g.DrawPath($pen, $path)
    $pen.Dispose()
    $bgBrush.Dispose()
    $path.Dispose()
}

function Draw-FourPointStar([System.Drawing.Graphics]$g, [float]$cx, [float]$cy, [float]$outerR, [float]$innerR, [System.Drawing.Color]$fill) {
    $pts = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
    for ($i = 0; $i -lt 8; $i++) {
        $ang = ($i * [Math]::PI / 4.0) - ([Math]::PI / 2.0)
        $r = if ($i % 2 -eq 0) { $outerR } else { $innerR }
        $pts.Add((New-Point ($cx + [Math]::Cos($ang) * $r) ($cy + [Math]::Sin($ang) * $r)))
    }
    $brush = [System.Drawing.SolidBrush]::new($fill)
    $g.FillPolygon($brush, $pts.ToArray())
    $brush.Dispose()
}

function Render-Icon([string]$key, [string]$filePath) {
    $bmp = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    $cyan = New-Color 65 210 255
    $gold = New-Color 255 205 45
    $mint = New-Color 95 215 145
    $cream = New-Color 245 240 232
    $ember = New-Color 255 120 75
    $emberDark = New-Color 155 58 38
    $violet = New-Color 205 115 255
    $slate = New-Color 98 112 144

    switch ($key) {
        "nav/Hub" {
            Draw-BadgeBase $g $cyan
            $domeBrush = [System.Drawing.SolidBrush]::new((New-Color 48 92 136))
            $g.FillPie($domeBrush, 56, 54, 144, 144, 180, 180)
            $pen = [System.Drawing.Pen]::new($cyan, 8)
            $g.DrawArc($pen, 56, 54, 144, 144, 180, 180)
            $baseBrush = [System.Drawing.SolidBrush]::new($cream)
            $g.FillRectangle($baseBrush, 46, 124, 164, 56)
            $doorBrush = [System.Drawing.SolidBrush]::new((New-Color 24 22 38))
            $g.FillRectangle($doorBrush, 110, 140, 36, 40)
            $scopePen = [System.Drawing.Pen]::new($gold, 14)
            $scopePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $scopePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($scopePen, 140, 88, 186, 52)
            Draw-FourPointStar $g 82 62 14 5 $gold
            $domeBrush.Dispose(); $pen.Dispose(); $baseBrush.Dispose(); $doorBrush.Dispose(); $scopePen.Dispose()
        }
        "nav/Ranch" {
            Draw-BadgeBase $g $mint
            $roofPts = [System.Drawing.PointF[]]@(
                (New-Point 48 122), (New-Point 128 56), (New-Point 208 122)
            )
            $roofBrush = [System.Drawing.SolidBrush]::new($mint)
            $g.FillPolygon($roofBrush, $roofPts)
            $barnBrush = [System.Drawing.SolidBrush]::new($cream)
            $g.FillRectangle($barnBrush, 68, 120, 120, 74)
            $doorBrush = [System.Drawing.SolidBrush]::new((New-Color 36 74 56))
            $g.FillRectangle($doorBrush, 108, 142, 40, 52)
            $fencePen = [System.Drawing.Pen]::new($gold, 8)
            $g.DrawLine($fencePen, 44, 184, 212, 184)
            $roofBrush.Dispose(); $barnBrush.Dispose(); $doorBrush.Dispose(); $fencePen.Dispose()
        }
        "nav/Bag" {
            Draw-BadgeBase $g $gold
            $handlePen = [System.Drawing.Pen]::new($gold, 12)
            $g.DrawArc($handlePen, 92, 48, 72, 54, 180, 180)
            $bodyPath = New-RoundedRectPath 56 80 144 118 22
            $bodyBrush = [System.Drawing.SolidBrush]::new((New-Color 66 96 156))
            $g.FillPath($bodyBrush, $bodyPath)
            $flapPath = New-RoundedRectPath 56 80 144 54 18
            $flapBrush = [System.Drawing.SolidBrush]::new($cyan)
            $g.FillPath($flapBrush, $flapPath)
            $claspBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillRectangle($claspBrush, 114, 116, 28, 30)
            $handlePen.Dispose(); $bodyPath.Dispose(); $bodyBrush.Dispose(); $flapPath.Dispose(); $flapBrush.Dispose(); $claspBrush.Dispose()
        }
        "nav/Guide" {
            Draw-BadgeBase $g $violet
            $bookPath = New-RoundedRectPath 58 56 140 144 14
            $bookBrush = [System.Drawing.SolidBrush]::new((New-Color 68 48 112))
            $g.FillPath($bookBrush, $bookPath)
            $bookPen = [System.Drawing.Pen]::new($violet, 7)
            $g.DrawPath($bookPen, $bookPath)
            $spineBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillRectangle($spineBrush, 68, 56, 18, 144)
            Draw-FourPointStar $g 142 126 34 13 $gold
            $bookPath.Dispose(); $bookBrush.Dispose(); $bookPen.Dispose(); $spineBrush.Dispose()
        }
        "nav/Shop" {
            Draw-BadgeBase $g $gold
            $coinBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillEllipse($coinBrush, 58, 58, 140, 140)
            $innerPen = [System.Drawing.Pen]::new((New-Color 184 128 18), 8)
            $g.DrawEllipse($innerPen, 74, 74, 108, 108)
            Draw-FourPointStar $g 128 128 36 14 (New-Color 255 245 190)
            $coinBrush.Dispose(); $innerPen.Dispose()
        }
        "nav/Settings" {
            Draw-BadgeBase $g $cream
            $gearBrush = [System.Drawing.SolidBrush]::new($cream)
            for ($i = 0; $i -lt 8; $i++) {
                $ang = $i * [Math]::PI / 4.0
                $tx = 128 + [Math]::Cos($ang) * 62
                $ty = 128 + [Math]::Sin($ang) * 62
                $g.FillEllipse($gearBrush, $tx - 14, $ty - 14, 28, 28)
            }
            $g.FillEllipse($gearBrush, 74, 74, 108, 108)
            $holeBrush = [System.Drawing.SolidBrush]::new((New-Color 24 27 46))
            $g.FillEllipse($holeBrush, 100, 100, 56, 56)
            $gearBrush.Dispose(); $holeBrush.Dispose()
        }
        "meteors/Ember" {
            Draw-BadgeBase $g $ember
            $rockPts = [System.Drawing.PointF[]]@(
                (New-Point 72 86), (New-Point 128 52), (New-Point 188 82),
                (New-Point 198 144), (New-Point 156 196), (New-Point 88 190), (New-Point 58 138)
            )
            $rockBrush = [System.Drawing.SolidBrush]::new($emberDark)
            $g.FillPolygon($rockBrush, $rockPts)
            $crackPen = [System.Drawing.Pen]::new($gold, 9)
            $crackPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $crackPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($crackPen, 92, 92, 134, 128)
            $g.DrawLine($crackPen, 134, 128, 114, 174)
            $g.DrawLine($crackPen, 134, 128, 176, 136)
            $coreBrush = [System.Drawing.SolidBrush]::new($ember)
            $g.FillEllipse($coreBrush, 116, 110, 32, 32)
            $rockBrush.Dispose(); $crackPen.Dispose(); $coreBrush.Dispose()
        }
        "meteors/Frost" {
            Draw-BadgeBase $g $cyan
            $hexPts = [System.Drawing.PointF[]]@(
                (New-Point 128 52), (New-Point 192 90), (New-Point 192 166),
                (New-Point 128 204), (New-Point 64 166), (New-Point 64 90)
            )
            $iceBrush = [System.Drawing.SolidBrush]::new((New-Color 56 142 196))
            $g.FillPolygon($iceBrush, $hexPts)
            $icePen = [System.Drawing.Pen]::new($cyan, 8)
            $g.DrawPolygon($icePen, $hexPts)
            $flakePen = [System.Drawing.Pen]::new($cream, 8)
            $g.DrawLine($flakePen, 128, 76, 128, 180)
            $g.DrawLine($flakePen, 82, 104, 174, 152)
            $g.DrawLine($flakePen, 174, 104, 82, 152)
            $iceBrush.Dispose(); $icePen.Dispose(); $flakePen.Dispose()
        }
        "meteors/Astral" {
            Draw-BadgeBase $g $violet
            $octPts = [System.Drawing.PointF[]]@(
                (New-Point 128 48), (New-Point 186 78), (New-Point 204 134),
                (New-Point 172 192), (New-Point 96 196), (New-Point 56 146), (New-Point 68 82)
            )
            $astBrush = [System.Drawing.SolidBrush]::new((New-Color 92 46 148))
            $g.FillPolygon($astBrush, $octPts)
            $astPen = [System.Drawing.Pen]::new($violet, 7)
            $g.DrawPolygon($astPen, $octPts)
            Draw-FourPointStar $g 128 124 42 16 $gold
            $astBrush.Dispose(); $astPen.Dispose()
        }
        "tools/StarterCracker" {
            Draw-BadgeBase $g $gold
            $shaftPen = [System.Drawing.Pen]::new($cream, 16)
            $shaftPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $shaftPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($shaftPen, 68, 188, 154, 102)
            $headPts = [System.Drawing.PointF[]]@(
                (New-Point 124 70), (New-Point 184 58), (New-Point 198 118), (New-Point 148 134)
            )
            $headBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillPolygon($headBrush, $headPts)
            $shaftPen.Dispose(); $headBrush.Dispose()
        }
        "tools/FrostCracker" {
            Draw-BadgeBase $g $cyan
            $shaftPen = [System.Drawing.Pen]::new($slate, 16)
            $shaftPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $shaftPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($shaftPen, 66, 190, 150, 106)
            $headPts = [System.Drawing.PointF[]]@(
                (New-Point 116 66), (New-Point 194 54), (New-Point 202 126), (New-Point 140 136)
            )
            $headBrush = [System.Drawing.SolidBrush]::new($cyan)
            $g.FillPolygon($headBrush, $headPts)
            Draw-FourPointStar $g 164 90 18 7 $cream
            $shaftPen.Dispose(); $headBrush.Dispose()
        }
        "tools/AstralCracker" {
            Draw-BadgeBase $g $violet
            $shaftPen = [System.Drawing.Pen]::new($gold, 16)
            $shaftPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $shaftPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($shaftPen, 66, 190, 150, 106)
            $headPts = [System.Drawing.PointF[]]@(
                (New-Point 114 66), (New-Point 196 52), (New-Point 204 128), (New-Point 138 136)
            )
            $headBrush = [System.Drawing.SolidBrush]::new($violet)
            $g.FillPolygon($headBrush, $headPts)
            Draw-FourPointStar $g 162 90 22 9 $gold
            $shaftPen.Dispose(); $headBrush.Dispose()
        }
        "upgrades/PenSlot" {
            Draw-BadgeBase $g $mint
            $postBrush = [System.Drawing.SolidBrush]::new($cream)
            $g.FillRectangle($postBrush, 58, 86, 22, 106)
            $g.FillRectangle($postBrush, 176, 86, 22, 106)
            $railBrush = [System.Drawing.SolidBrush]::new($mint)
            $g.FillRectangle($railBrush, 48, 108, 160, 20)
            $g.FillRectangle($railBrush, 48, 150, 160, 20)
            Draw-FourPointStar $g 128 74 20 8 $gold
            $postBrush.Dispose(); $railBrush.Dispose()
        }
        "upgrades/Incubator" {
            Draw-BadgeBase $g $cyan
            $baseBrush = [System.Drawing.SolidBrush]::new($slate)
            $g.FillRectangle($baseBrush, 58, 162, 140, 34)
            $glassBrush = [System.Drawing.SolidBrush]::new((New-Color 65 210 255 150))
            $g.FillEllipse($glassBrush, 74, 58, 108, 118)
            $glassPen = [System.Drawing.Pen]::new($cyan, 8)
            $g.DrawEllipse($glassPen, 74, 58, 108, 118)
            $eggBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillEllipse($eggBrush, 104, 88, 48, 60)
            $baseBrush.Dispose(); $glassBrush.Dispose(); $glassPen.Dispose(); $eggBrush.Dispose()
        }
        "upgrades/BagCap" {
            Draw-BadgeBase $g $gold
            $bagPath = New-RoundedRectPath 58 84 140 112 22
            $bagBrush = [System.Drawing.SolidBrush]::new((New-Color 66 96 156))
            $g.FillPath($bagBrush, $bagPath)
            $plusBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillRectangle($plusBrush, 116, 108, 24, 64)
            $g.FillRectangle($plusBrush, 96, 128, 64, 24)
            $arrowPts = [System.Drawing.PointF[]]@(
                (New-Point 128 46), (New-Point 156 76), (New-Point 100 76)
            )
            $g.FillPolygon($plusBrush, $arrowPts)
            $bagPath.Dispose(); $bagBrush.Dispose(); $plusBrush.Dispose()
        }
        "upgrades/FrostLure" {
            Draw-BadgeBase $g $cyan
            $towerBrush = [System.Drawing.SolidBrush]::new($slate)
            $g.FillRectangle($towerBrush, 112, 116, 32, 78)
            $g.FillRectangle($towerBrush, 82, 180, 92, 18)
            $ringPen = [System.Drawing.Pen]::new($cyan, 8)
            $g.DrawArc($ringPen, 72, 54, 112, 112, 200, 140)
            $g.DrawArc($ringPen, 92, 72, 72, 72, 200, 140)
            $orbBrush = [System.Drawing.SolidBrush]::new($gold)
            $g.FillEllipse($orbBrush, 108, 92, 40, 40)
            $towerBrush.Dispose(); $ringPen.Dispose(); $orbBrush.Dispose()
        }
    }

    $dir = Split-Path -Parent $filePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $bmp.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

$icons = @(
    "nav/Hub", "nav/Ranch", "nav/Bag", "nav/Guide",
    "nav/Shop", "nav/Settings", "meteors/Ember", "meteors/Frost",
    "meteors/Astral", "tools/StarterCracker", "tools/FrostCracker", "tools/AstralCracker",
    "upgrades/PenSlot", "upgrades/Incubator", "upgrades/BagCap", "upgrades/FrostLure"
)

$manifest = [ordered]@{}
foreach ($key in $icons) {
    $relPng = "$key.png"
    $fullPath = Join-Path $OutDir ($relPng -replace "/", "\")
    Render-Icon $key $fullPath
    $manifest[$key] = "tools/art/icons_png/$relPng"
}

$manifestPath = Join-Path $OutDir "manifest.json"
$manifest | ConvertTo-Json -Depth 2 | Set-Content -Path $manifestPath -Encoding UTF8

# Render 4x4 labeled contact sheet
$sheetW = 1024
$sheetH = 1120
$sheet = [System.Drawing.Bitmap]::new($sheetW, $sheetH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sg = [System.Drawing.Graphics]::FromImage($sheet)
$sg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$sg.Clear((New-Color 18 22 42))

$font = [System.Drawing.Font]::new("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$textBrush = [System.Drawing.SolidBrush]::new((New-Color 238 234 224))
$cellW = 256
$cellH = 280
for ($idx = 0; $idx -lt $icons.Count; $idx++) {
    $col = $idx % 4
    $row = [Math]::Floor($idx / 4)
    $x = $col * $cellW
    $y = $row * $cellH
    $iconBmp = [System.Drawing.Bitmap]::FromFile((Join-Path $OutDir (($icons[$idx] + ".png") -replace "/", "\")))
    $sg.DrawImage($iconBmp, $x + 28, $y + 12, 200, 200)
    $iconBmp.Dispose()
    $sf = [System.Drawing.StringFormat]::new()
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sg.DrawString($icons[$idx], $font, $textBrush, [System.Drawing.RectangleF]::new($x, $y + 224, $cellW, 36), $sf)
    $sf.Dispose()
}
$font.Dispose()
$textBrush.Dispose()
$sg.Dispose()

$sheetPath = Join-Path $OutDir "contact_sheet.png"
$sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()

Write-Host "Rendered $($icons.Count) PNG icons + contact_sheet.png to $OutDir"
