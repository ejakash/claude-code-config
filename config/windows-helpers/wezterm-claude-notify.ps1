param(
  [string]$Label = "",
  [string]$WindowTitle = "",
  [switch]$Raise
)

[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null

# Strip XML-special chars, then XML 1.0 illegal control chars (everything
# <0x20 except tab/LF/CR). WSL paths can contain newlines that would
# otherwise crash LoadXml below.
$safe = ($Label -replace '[<>&"''`]', '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
$body = if ($safe) { "$safe - waiting for input" } else { "waiting for input" }
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>Claude Code</text><text>$body</text></binding></visual></toast>")
$t = [Windows.UI.Notifications.ToastNotification]::new($xml)
# <-- edit per machine: Claude Desktop AUMID (discover via `powershell.exe Get-StartApps | ? Name -like '*Claude*'`)
$aumid = 'Claude_pzs8sxrjxfjjc!Claude'
try {
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show($t)
} catch {
  # background_child_process swallows stdout/stderr, but WezTerm's debug
  # overlay captures stderr from spawned processes. Writing the failure
  # there turns "no toast and no error" into a discoverable clue when
  # the AUMID doesn't match this machine's Claude Desktop install.
  [Console]::Error.WriteLine("wezterm-claude-notify: CreateToastNotifier('$aumid') failed: $($_.Exception.Message)")
  [Console]::Error.WriteLine("Run config\windows-helpers\preflight.ps1 to discover the correct AUMID.")
}

# Raise WezTerm from a non-foreground process. Windows blocks plain
# SetForegroundWindow here; the fake ALT tap bypasses that protection
# (standard Windows workaround used by many apps).
if ($Raise) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
'@
  $procs = Get-Process -Name 'wezterm-gui','wezterm' -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowHandle -ne 0 }
  # With multiple WezTerm windows, pick the one whose MainWindowTitle
  # matches the calling WezTerm window's active tab title. Falls back to
  # the oldest (first) process if nothing matches.
  $proc = $null
  if ($WindowTitle) {
    # -like treats [, *, ? as wildcards. Tab titles commonly contain
    # brackets (e.g. "[1]") and stars (vim dirty markers), so escape.
    $pat = [System.Management.Automation.WildcardPattern]::Escape($WindowTitle)
    $proc = $procs | Where-Object { $_.MainWindowTitle -like "*$pat*" } | Select-Object -First 1
  }
  if (-not $proc) { $proc = $procs | Select-Object -First 1 }
  if ($proc) {
    $hwnd = $proc.MainWindowHandle
    if ([Win32]::IsIconic($hwnd)) { [Win32]::ShowWindow($hwnd, 9) }  # SW_RESTORE
    [Win32]::keybd_event(0x12, 0, 1, [UIntPtr]::Zero)   # ALT down
    [Win32]::keybd_event(0x12, 0, 3, [UIntPtr]::Zero)   # ALT up
    [Win32]::SetForegroundWindow($hwnd) | Out-Null
  }
}
