#Requires -Version 5.1
<#
================================================================================
  Build ProtonPortSync.exe from ProtonPortSync.ps1
================================================================================

  Run this whenever you change the script OR the logo:

      powershell -ExecutionPolicy Bypass -File Build-ProtonPortSync.ps1

  It looks for the script, the logo and the exe alongside itself, so it works
  from whatever folder you keep it in. Nothing to configure.

  It does three things:
    1. Turns the logo PNG into a proper multi-size Windows icon (.ico).
    2. Compiles the script into ProtonPortSync.exe with that icon.
    3. Copies the exe to your Desktop.

  About the logo: it does NOT need to be square. Anything that is not square gets
  centred on a see-through square canvas, so the picture is never stretched or
  squashed. A square PNG will still look tidier, because you choose the spacing
  instead of the padding choosing it for you.

  About the sizes: Windows shows a different size in different places - small in
  a title bar, medium on the taskbar, large in an Explorer window. A .ico that
  holds only one size gets scaled badly everywhere else, so this builds seven.
================================================================================
#>

[CmdletBinding()]
param(
    # Left empty on purpose. They are filled in below from wherever this script
    # lives, so the whole thing works from any folder with nothing to edit.
    # They CANNOT be defaulted up here: $PSScriptRoot is still empty while
    # parameter defaults are being worked out, so Join-Path fails.
    [string] $Logo,
    [string] $Script,
    [string] $Exe,
    [string] $Icon,
    [switch] $NoDesktopCopy
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $root) { $root = (Get-Location).Path }
if (-not $Logo)   { $Logo   = Join-Path $root 'ProtonVPN_qBittorrent_Logo.png' }
if (-not $Script) { $Script = Join-Path $root 'ProtonPortSync.ps1' }
if (-not $Exe)    { $Exe    = Join-Path $root 'ProtonPortSync.exe' }
if (-not $Icon)   { $Icon   = Join-Path $root 'ProtonPortSync.ico' }

function Write-Step { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Info { param([string]$m) Write-Host "   $m" -ForegroundColor DarkGray }

# ------------------------------------------------------- 1. logo -> icon ----

function New-IconDib {
    <# One image inside an .ico: a header, the colours bottom-up, then a 1-bit mask. #>
    param([System.Drawing.Bitmap]$Source, [int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr  = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.Clear([System.Drawing.Color]::Transparent)
    $gr.InterpolationMode  = 'HighQualityBicubic'
    $gr.SmoothingMode      = 'HighQuality'
    $gr.PixelOffsetMode    = 'HighQuality'
    $gr.CompositingQuality = 'HighQuality'
    $gr.DrawImage($Source, 0, 0, $Size, $Size)
    $gr.Dispose()

    $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = New-Object byte[] ($data.Stride * $Size)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    $stride = $data.Stride
    $bmp.UnlockBits($data)

    $maskStride = [int]([Math]::Floor(($Size + 31) / 32)) * 4
    $xorSize    = $Size * $Size * 4
    $andSize    = $maskStride * $Size

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # BITMAPINFOHEADER. The height is doubled because it covers colours AND mask.
    $bw.Write([uint32]40); $bw.Write([int32]$Size); $bw.Write([int32]($Size * 2))
    $bw.Write([uint16]1);  $bw.Write([uint16]32);   $bw.Write([uint32]0)
    $bw.Write([uint32]($xorSize + $andSize))
    $bw.Write([int32]0); $bw.Write([int32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)

    for ($y = $Size - 1; $y -ge 0; $y--) { $bw.Write($pixels, $y * $stride, $Size * 4) }
    $bw.Write((New-Object byte[] $andSize), 0, $andSize)   # all zero = alpha does the see-through

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose(); $bmp.Dispose()
    return $bytes
}

function New-IconPng {
    <# The big 256 image is stored as a PNG inside the .ico, not as a raw bitmap.
       That is what Windows and every real icon file does, and a raw 256 bitmap
       is quietly ignored by some readers - which is exactly what happened here
       on the first build: asking for 256 handed back the 128 one instead. #>
    param([System.Drawing.Bitmap]$Source, [int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gr  = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.Clear([System.Drawing.Color]::Transparent)
    $gr.InterpolationMode  = 'HighQualityBicubic'
    $gr.SmoothingMode      = 'HighQuality'
    $gr.PixelOffsetMode    = 'HighQuality'
    $gr.CompositingQuality = 'HighQuality'
    $gr.DrawImage($Source, 0, 0, $Size, $Size)
    $gr.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose(); $bmp.Dispose()
    return $bytes
}

function ConvertTo-Icon {
    param([string]$PngPath, [string]$IcoPath, [int[]]$Sizes = @(16, 24, 32, 48, 64, 128, 256))

    $src = [System.Drawing.Bitmap]::FromFile($PngPath)
    try {
        Write-Info ("logo is {0} x {1}" -f $src.Width, $src.Height)

        $side   = [Math]::Max($src.Width, $src.Height)
        $square = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($square)
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($src, [int](($side - $src.Width) / 2), [int](($side - $src.Height) / 2), $src.Width, $src.Height)
        $g.Dispose()
        if ($src.Width -ne $src.Height) { Write-Info ("not square, so centred on a {0} x {0} see-through canvas" -f $side) }

        $images = @()
        foreach ($s in $Sizes) {
            # 256 and above go in as PNG, everything smaller as a raw bitmap.
            if ($s -ge 256) { $bytes = New-IconPng -Source $square -Size $s }
            else            { $bytes = New-IconDib -Source $square -Size $s }
            $images += ,@{ Size = $s; Bytes = $bytes }
        }

        $fs = [System.IO.File]::Create($IcoPath)
        $bw = New-Object System.IO.BinaryWriter($fs)
        $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$images.Count)
        $offset = 6 + (16 * $images.Count)
        foreach ($img in $images) {
            $dim = $img.Size; if ($dim -ge 256) { $dim = 0 }   # 0 is how 256 is recorded
            $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
            $bw.Write([uint16]1);  $bw.Write([uint16]32)
            $bw.Write([uint32]$img.Bytes.Length); $bw.Write([uint32]$offset)
            $offset += $img.Bytes.Length
        }
        foreach ($img in $images) { $bw.Write($img.Bytes, 0, $img.Bytes.Length) }
        $bw.Flush(); $bw.Dispose(); $fs.Dispose()
        $square.Dispose()

        Write-Info ("wrote {0} sizes: {1}" -f $images.Count, ($Sizes -join ', '))
    } finally { $src.Dispose() }
}

# ------------------------------------------------------------- run it -------

Write-Step "`n1. logo -> icon"
if (-not (Test-Path -LiteralPath $Logo)) { throw "Logo not found: $Logo" }
ConvertTo-Icon -PngPath $Logo -IcoPath $Icon
Write-Info ("{0}  ({1:N0} bytes)" -f (Split-Path $Icon -Leaf), (Get-Item $Icon).Length)

# Read the finished file's own directory back, so a broken icon is caught here
# and not discovered later as a blank square on the Desktop.
# Deliberately NOT using System.Drawing.Icon for this: it cannot read a 256px
# entry at all and quietly hands back the next size down, which reads as a
# failure when the file is perfectly fine.
$raw   = [System.IO.File]::ReadAllBytes($Icon)
$count = [BitConverter]::ToUInt16($raw, 4)
if ($count -ne $Sizes.Count -and $count -ne 7) { Write-Host "  expected 7 images, found $count" -ForegroundColor Yellow }
for ($i = 0; $i -lt $count; $i++) {
    $o = 6 + ($i * 16)
    $w = $raw[$o]; if ($w -eq 0) { $w = 256 }
    $len = [BitConverter]::ToUInt32($raw, $o + 8)
    $off = [BitConverter]::ToUInt32($raw, $o + 12)
    $isPng = ($raw[$off] -eq 0x89 -and $raw[$off+1] -eq 0x50 -and $raw[$off+2] -eq 0x4E -and $raw[$off+3] -eq 0x47)
    $kind = 'bitmap'; if ($isPng) { $kind = 'PNG' }
    if ($off + $len -gt $raw.Length) { throw "Icon entry $w is truncated - the file is corrupt." }
    Write-Info ("{0,3}px  {1,-6}  {2,7:N0} bytes" -f $w, $kind, $len)
}

Write-Step "`n2. script -> exe"
if (-not (Test-Path -LiteralPath $Script)) { throw "Script not found: $Script" }
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$errs)
if ($errs) { $errs | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }; throw 'The script has syntax errors. Not building.' }
Write-Info 'syntax OK'

Import-Module ps2exe -ErrorAction Stop
Invoke-ps2exe -inputFile $Script -outputFile $Exe -iconFile $Icon `
              -title 'ProtonVPN to qBittorrent port sync' `
              -description 'Reads the ProtonVPN forwarded port and applies it to qBittorrent' `
              -company 'omv421' -product 'ProtonPortSync' -version '2.0.0.0'
if (-not (Test-Path -LiteralPath $Exe)) { throw 'ps2exe did not produce an exe.' }
Write-Info ("{0}  ({1:N0} bytes)" -f (Split-Path $Exe -Leaf), (Get-Item $Exe).Length)

if (-not $NoDesktopCopy) {
    Write-Step "`n3. copy to Desktop"
    $dest = Join-Path ([Environment]::GetFolderPath('Desktop')) (Split-Path $Exe -Leaf)
    Copy-Item -LiteralPath $Exe -Destination $dest -Force
    Write-Info $dest
}

if ($NoDesktopCopy) {
    Write-Host "`nDone. Your exe is at:`n  $Exe`n" -ForegroundColor Green
} else {
    Write-Host "`nDone. Double-click ProtonPortSync.exe on the Desktop.`n" -ForegroundColor Green
}
