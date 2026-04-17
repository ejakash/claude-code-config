-- claude-waiting.lua — WezTerm notification module for Claude Code idle state.
--
-- Exposes an apply(config, wezterm) entry point that registers all event
-- handlers, keybindings, and mouse bindings for the feature. The host
-- `.wezterm.lua` only needs:
--
--   local claude_waiting = dofile("C:\\Users\\<WIN_USER>\\.wezterm-claude-waiting.lua")
--   claude_waiting.apply(config, wezterm)
--
-- For tab amber rendering, call format_tab_title_overlay from inside the
-- host's existing format-tab-title handler (WezTerm only fires the last
-- registered handler, so this must be a merge point, not a separate one).
--
-- Requires: WezTerm on Windows + WSL2 + Claude Desktop (for AUMID toast).

local M = {}

local CLAUDE_WAITING_BG     = "#2a2018"
local CLAUDE_WAITING_TAB_BG = "#e0af68"
local CLAUDE_WAITING_TAB_FG = "#1a1b26"

-- <-- edit per machine: Windows username in path below
M.toast_script = "C:\\Users\\spirit\\.wezterm-claude-notify.ps1"

local function clear_waiting(pane)
  pane:inject_output("\x1b]1337;SetUserVar=CLAUDE_WAITING=MA==\x07")  -- MA== = base64("0")
end

-- Call from inside the host's format-tab-title handler. Returns a
-- styled-text array if any pane in the tab has CLAUDE_WAITING=1, else nil
-- (in which case the host proceeds with its default formatting).
function M.format_tab_title_overlay(wezterm, tab, label)
  local mux_tab = wezterm.mux.get_tab(tab.tab_id)
  if not mux_tab then return nil end
  for _, pane in ipairs(mux_tab:panes()) do
    if pane:get_user_vars().CLAUDE_WAITING == "1" then
      return {
        { Background = { Color = CLAUDE_WAITING_TAB_BG } },
        { Foreground = { Color = CLAUDE_WAITING_TAB_FG } },
        { Text = label },
      }
    end
  end
  return nil
end

function M.apply(config, wezterm)
  wezterm.GLOBAL.last_active_pane = wezterm.GLOBAL.last_active_pane or {}

  -- wezterm.GLOBAL persists across config reloads. Entries can reference
  -- window_ids / pane_ids that no longer exist, or (worse) window_ids
  -- whose ID got reused for a fresh window. Reset on reload — the
  -- update-status tick will repopulate within ~1s.
  wezterm.on("window-config-reloaded", function(_)
    wezterm.GLOBAL.last_active_pane = {}
  end)

  -- Decision handler: fired whenever CLAUDE_WAITING flips via OSC 1337.
  wezterm.on("user-var-changed", function(window, pane, name, value)
    if name ~= "CLAUDE_WAITING" then return end

    -- value=0: single source of truth for bg reset. Any clearer (hook,
    -- click, activation) just flips the var; OSC 111 lives only here.
    if value == "0" then
      pane:inject_output("\x1b]111\x1b\\")
      return
    end
    if value ~= "1" then return end

    -- Self-suppression: if user is already on this pane in a focused
    -- WezTerm, don't alert at all — flip straight back to 0.
    local active = window:active_pane()
    local focused = window:is_focused()
    if active and active:pane_id() == pane:pane_id() and focused then
      clear_waiting(pane)
      return
    end

    -- Tint the waiting pane's background.
    pane:inject_output("\x1b]11;" .. CLAUDE_WAITING_BG .. "\x1b\\")

    -- If WezTerm is backgrounded, auto-switch to the waiting tab and
    -- preempt last_active_pane so update-status doesn't treat the
    -- programmatic activation as user interaction and clear the tint.
    if not focused then
      local mux_tab = pane:tab()
      if mux_tab then
        mux_tab:activate()
        local new_active = window:active_pane()
        if new_active then
          wezterm.GLOBAL.last_active_pane[tostring(window:window_id())] = new_active:pane_id()
        end
      end
    end

    -- Label for the toast body: basename of the pane's cwd.
    local cwd = pane:get_current_working_dir()
    local label = ""
    if cwd then
      local path = (type(cwd) == "string") and cwd or cwd.file_path
      if path then label = path:match("([^/]+)/?$") or "" end
    end

    -- Window title: lets the PS1 match the right HWND when multiple
    -- WezTerm windows are open.
    local mux_win = window:mux_window()
    local title = ""
    if mux_win then
      local active_tab = mux_win:active_tab()
      if active_tab then title = active_tab:get_title() or "" end
    end

    local args = {
      "powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
      "-File", M.toast_script,
      "-Label", label,
      "-WindowTitle", title,
    }
    if not focused then table.insert(args, "-Raise") end
    wezterm.background_child_process(args)
  end)

  -- Clear path #1 (keyboard nav / tab switch): update-status fires ~1/s
  -- per window. If the active pane changed and the new one is waiting,
  -- clear it. Coexists with any existing update-status handler.
  wezterm.on("update-status", function(window, pane)
    local key = tostring(window:window_id())
    local current = pane:pane_id()
    local last = wezterm.GLOBAL.last_active_pane[key]
    if last ~= current then
      wezterm.GLOBAL.last_active_pane[key] = current
      if last ~= nil and pane:get_user_vars().CLAUDE_WAITING == "1" then
        clear_waiting(pane)
      end
    end
  end)

  -- Clear path #2 (click-in-same-pane): update-status misses this because
  -- the active pane didn't change. Mouse binding fills the gap; it still
  -- performs the default selection/open-link action so copy-on-click works.
  config.mouse_bindings = config.mouse_bindings or {}
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "NONE",
    action = wezterm.action_callback(function(window, pane)
      if pane:get_user_vars().CLAUDE_WAITING == "1" then
        clear_waiting(pane)
      end
      window:perform_action(
        wezterm.action.CompleteSelectionOrOpenLinkAtMouseCursor("ClipboardAndPrimarySelection"),
        pane
      )
    end),
  })

  -- Alt+N: jump to the first waiting pane anywhere in this window. The
  -- activation naturally triggers the update-status clear path.
  config.keys = config.keys or {}
  table.insert(config.keys, {
    key = "n", mods = "ALT",
    action = wezterm.action_callback(function(window, _)
      local mw = window:mux_window()
      if not mw then return end
      for _, t in ipairs(mw:tabs()) do
        for _, p in ipairs(t:panes()) do
          if p:get_user_vars().CLAUDE_WAITING == "1" then
            p:activate()
            return
          end
        end
      end
    end),
  })
end

return M
