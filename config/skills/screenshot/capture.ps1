param(
    [Parameter(Position=0)]
    [ValidateSet("overview", "crop", "list")]
    [string]$Mode = "overview",

    # For crop mode: which capture to zoom into
    [string]$CaptureId,

    # Crop region as percentages (0-100) of the full image
    [float]$Left = 0,
    [float]$Top = 0,
    [float]$Right = 100,
    [float]$Bottom = 100
)

Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class DPI { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
[DPI]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms,System.Drawing

$screenshotDir = "$env:USERPROFILE\Pictures\Screenshots"
$tempDir = "$env:TEMP\claude-screenshots"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# Cleanup: remove temp captures older than 1 hour
Get-ChildItem $tempDir -Filter "capture_*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

if ($Mode -eq "list") {
    # List available captures for reference
    $captures = Get-ChildItem $tempDir -Filter "capture_*.png" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { $_.BaseName -replace '^capture_', '' }
    if ($captures) {
        Write-Host "available_captures|$($captures -join ',')"
    } else {
        Write-Host "available_captures|none"
    }
    exit 0
}

if ($Mode -eq "overview") {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    # Generate unique capture ID
    $captureId = Get-Date -Format 'yyyyMMdd_HHmmss_fff'

    # Capture full screen at native resolution
    $full = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($full)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $g.Dispose()

    # Save full-res with unique ID for later cropping
    $tempPath = Join-Path $tempDir "capture_${captureId}.png"
    $full.Save($tempPath)

    # Create overview (1200px long edge, ~1080 tokens)
    $ratio = [Math]::Min(1200.0 / $bounds.Width, 1200.0 / $bounds.Height)
    $ow = [int]($bounds.Width * $ratio)
    $oh = [int]($bounds.Height * $ratio)
    $overview = New-Object System.Drawing.Bitmap($ow, $oh)
    $g2 = [System.Drawing.Graphics]::FromImage($overview)
    $g2.InterpolationMode = 'HighQualityBicubic'
    $g2.DrawImage($full, 0, 0, $ow, $oh)
    $g2.Dispose()
    $full.Dispose()

    $outPath = Join-Path $screenshotDir "Screenshot ${captureId}.png"
    $overview.Save($outPath)
    $overview.Dispose()

    Write-Host "overview|$outPath|${ow}x${oh}|capture_id=${captureId}"
}
elseif ($Mode -eq "crop") {
    if (-not $CaptureId) {
        # Default to most recent capture
        $latest = Get-ChildItem $tempDir -Filter "capture_*.png" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            Write-Error "No captures available. Run 'overview' first."
            exit 1
        }
        $CaptureId = $latest.BaseName -replace '^capture_', ''
    }

    $tempPath = Join-Path $tempDir "capture_${CaptureId}.png"
    if (-not (Test-Path $tempPath)) {
        Write-Error "Capture '$CaptureId' not found. Run 'list' to see available captures."
        exit 1
    }

    $full = [System.Drawing.Image]::FromFile($tempPath)

    # Convert percentage coordinates to pixels
    $px_left   = [int]($Left   / 100.0 * $full.Width)
    $px_top    = [int]($Top    / 100.0 * $full.Height)
    $px_right  = [int]($Right  / 100.0 * $full.Width)
    $px_bottom = [int]($Bottom / 100.0 * $full.Height)
    $px_w = $px_right - $px_left
    $px_h = $px_bottom - $px_top

    # Crop from full-res
    $cropRect = New-Object System.Drawing.Rectangle($px_left, $px_top, $px_w, $px_h)
    $cropped = ([System.Drawing.Bitmap]$full).Clone($cropRect, $full.PixelFormat)
    $full.Dispose()

    # Scale crop to 1568px long edge for optimal Claude processing
    $maxDim = 1568.0
    $ratio = [Math]::Min($maxDim / $cropped.Width, $maxDim / $cropped.Height)
    if ($ratio -lt 1.0) {
        $nw = [int]($cropped.Width * $ratio)
        $nh = [int]($cropped.Height * $ratio)
    } else {
        $nw = $cropped.Width
        $nh = $cropped.Height
    }
    $final = New-Object System.Drawing.Bitmap($nw, $nh)
    $g = [System.Drawing.Graphics]::FromImage($final)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($cropped, 0, 0, $nw, $nh)
    $g.Dispose()
    $cropped.Dispose()

    $outPath = Join-Path $screenshotDir "Screenshot ${CaptureId}_crop.png"
    $final.Save($outPath)
    $final.Dispose()

    Write-Host "crop|$outPath|${nw}x${nh}|capture_id=${CaptureId}|region=${Left},${Top},${Right},${Bottom}"
}
