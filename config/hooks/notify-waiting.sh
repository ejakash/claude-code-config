#!/usr/bin/env bash
# Claude Code waiting-state signal for WezTerm.
#
# Usage: notify-waiting.sh <1|0>
#   1 = waiting   (Stop hook)
#   0 = not waiting (UserPromptSubmit hook)
#
# Writes OSC 1337 SetUserVar=CLAUDE_WAITING=<val> to the pane's pty.
# All downstream logic (tint, toast, window raise, tab amber) lives in
# the WezTerm Lua module claude-waiting.lua.
#
# Requires: Linux /proc + /dev/pts. WSL2 only — exits silently elsewhere.
# Inside tmux: no-op. The process tree makes pty routing unreliable
# (tmux client ptys can shadow the real WezTerm pane pts), so we'd end
# up marking the wrong pane as waiting. Documented limitation.

[ -n "${TMUX:-}" ] && exit 0

case "${1:-}" in
  1) VAL="MQ==" ;;  # base64 "1"
  0) VAL="MA==" ;;  # base64 "0"
  *) exit 2 ;;
esac

find_tty() {
  local pid=${1:-$$}
  while [ "$pid" -gt 1 ]; do
    for fd in 0 1 2; do
      local link
      link=$(readlink "/proc/$pid/fd/$fd" 2>/dev/null)
      if [[ "$link" == /dev/pts/* ]]; then
        echo "$link"
        return 0
      fi
    done
    pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null) || break
  done
  return 1
}

TTY_PATH=$(find_tty $$) || exit 0
# 2>/dev/null: if the pane closed between hook firing and now, the pty
# symlink may be gone. Silent no-op is the right behavior — the Stop
# event is advisory, not authoritative.
printf "\033]1337;SetUserVar=CLAUDE_WAITING=%s\007" "$VAL" > "$TTY_PATH" 2>/dev/null
