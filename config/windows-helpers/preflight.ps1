# preflight.ps1 — detects the machine-specific values required to enable
# the Claude waiting-notification feature on this Windows host.
#
# Run from PowerShell:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\preflight.ps1
#
# Prints:
#   - Claude Desktop AUMID (for wezterm-claude-notify.ps1)
#   - WezTerm version (feature requires background_child_process + is_focused)
#   - Windows username (for the CLAUDE_TOAST_SCRIPT Lua path)
# An onboarding agent can read this output and fill in the two
# edit-per-machine slots automatically.

Write-Host "=== Claude waiting-notification preflight ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Windows username:" -ForegroundColor Yellow
Write-Host "  $env:USERNAME"
Write-Host ""

Write-Host "Claude Desktop AUMID:" -ForegroundColor Yellow
$claude = Get-StartApps | Where-Object Name -like '*Claude*'
if ($claude) {
  $claude | ForEach-Object { Write-Host ("  {0,-20} {1}" -f $_.Name, $_.AppID) }
  $primary = ($claude | Where-Object AppID -like 'Claude_*' | Select-Object -First 1)
  if ($primary) {
    Write-Host ""
    Write-Host "  → Use this value in wezterm-claude-notify.ps1:" -ForegroundColor Green
    Write-Host "    $($primary.AppID)"
  }
} else {
  Write-Host "  NOT FOUND — Claude Desktop does not appear to be installed." -ForegroundColor Red
  Write-Host "  Toasts will fail silently until Claude Desktop is installed."
}
Write-Host ""

Write-Host "WezTerm:" -ForegroundColor Yellow
$wez = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if ($wez) {
  $ver = & wezterm.exe --version 2>&1
  Write-Host "  $ver"
  Write-Host "  path: $($wez.Source)"
} else {
  Write-Host "  wezterm.exe NOT on PATH — cannot detect version." -ForegroundColor Red
  Write-Host "  The feature requires a recent-ish WezTerm with background_child_process,"
  Write-Host "  window:is_focused(), and MuxTab:panes()."
}
Write-Host ""

Write-Host "Toast helper + Lua module destination:" -ForegroundColor Yellow
Write-Host "  C:\Users\$env:USERNAME\.wezterm-claude-notify.ps1"
Write-Host "  C:\Users\$env:USERNAME\.wezterm-claude-waiting.lua"
Write-Host ""

Write-Host "=== Done ===" -ForegroundColor Cyan
