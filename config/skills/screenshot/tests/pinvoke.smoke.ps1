. (Join-Path (Split-Path $PSScriptRoot -Parent) 'capture.ps1') -DotSourceOnly
$hwnd = [Win32]::GetForegroundWindow()
if ($hwnd -eq [IntPtr]::Zero) { throw 'GetForegroundWindow returned zero' }
$rect = New-Object Win32+RECT
$ok = [Win32]::GetWindowRect($hwnd, [ref]$rect)
if (-not $ok) { throw 'GetWindowRect failed' }
Write-Host "OK hwnd=$hwnd rect=$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
