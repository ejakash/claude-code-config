#!/usr/bin/env bash
# Claude Code Stop hook — notify user that Claude is waiting for input
# Repo copy. The machine-specific path is in config/settings.json (<-- edit per machine).
#
# Behavior:
#   1. Play Windows chime (always, even outside WezTerm)
#   2. If WEZTERM_PANE is unset, exit (not in WezTerm)
#   3. Mark the pane with CLAUDE_WAITING=1 user var
#   4. If WezTerm is already foreground, exit (highlight is enough)
#   5. Switch to the waiting tab and raise WezTerm window

set -euo pipefail

# Step 1: Sound (synchronous ~1s; hook runs async via settings.json so Claude isn't blocked)
powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command \
  "[System.Media.SystemSounds]::Asterisk.Play()" || true

# Step 2: Guard — only proceed if running inside WezTerm
[ -z "${WEZTERM_PANE:-}" ] && exit 0

# Step 3: Mark the pane as waiting
wezterm cli set-user-var --pane-id "$WEZTERM_PANE" CLAUDE_WAITING 1

# Step 4: Check if WezTerm is already the foreground window
FOREGROUND_PROC=$(powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32Fg {
    [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
    [DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
}
'@
  \$hwnd = [Win32Fg]::GetForegroundWindow()
  \$procId = 0
  [Win32Fg]::GetWindowThreadProcessId(\$hwnd, [ref]\$procId) | Out-Null
  (Get-Process -Id \$procId -ErrorAction SilentlyContinue).ProcessName
" 2>/dev/null | tr -d '\r')

# wezterm-gui (typical install) or wezterm (some installs)
case "${FOREGROUND_PROC:-}" in
  wezterm*) exit 0 ;;
esac

# Step 5: Switch to the waiting pane, then raise WezTerm window
wezterm cli activate-pane --pane-id "$WEZTERM_PANE"

powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
  \$proc = Get-Process -Name 'wezterm-gui','wezterm' -ErrorAction SilentlyContinue |
             Where-Object { \$_.MainWindowHandle -ne 0 } |
             Select-Object -First 1
  if (\$proc) {
    [Win32]::ShowWindow(\$proc.MainWindowHandle, 9)   # SW_RESTORE
    [Win32]::SetForegroundWindow(\$proc.MainWindowHandle)
  }
"
