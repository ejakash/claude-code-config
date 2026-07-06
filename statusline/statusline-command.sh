#!/usr/bin/env bash
# Claude Code status line — clean two-line layout
# Tokyo Night palette, muted base + single accent, cost color encodes peak state

input=$(cat)

folder_icon=$'\xef\x81\xbc'
DOT=' · '

# --- Parse JSON via python3 ---
IFS='|' read -r model dir_name \
  in_tok out_tok cache_read cache_create \
  ctx_used_pct ctx_total \
  five_h_pct seven_d_pct \
  five_h_resets seven_d_resets \
  duration_ms cost_usd \
  eph_5m eph_1h hit_pct \
  < <(echo "$input" | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
m = d.get('model', {}).get('display_name', '?')
cwd = d.get('cwd', '')
dn = cwd.rsplit('/', 1)[-1] if cwd else '~'
session_id = d.get('session_id', '')

cw = d.get('context_window', {})
cu = cw.get('current_usage', {})
in_tok  = cu.get('input_tokens', 0)
out_tok = cu.get('output_tokens', 0)
cr = cu.get('cache_read_input_tokens', 0)
cc = cu.get('cache_creation_input_tokens', 0)
used_pct = cw.get('used_percentage', '')
ctx_total = cw.get('context_window_size', 0)

rl = d.get('rate_limits', {})
fh = rl.get('five_hour', {}).get('used_percentage', '')
sd = rl.get('seven_day', {}).get('used_percentage', '')
fh_r = rl.get('five_hour', {}).get('resets_at', '')
sd_r = rl.get('seven_day', {}).get('resets_at', '')

cost = d.get('cost', {})
dur = cost.get('total_duration_ms', 0)
usd = cost.get('total_cost_usd', 0)

# Sum cumulative usage across all assistant messages in the session transcript
eph_5m = 0
eph_1h = 0
out_total = 0
in_total = 0
cr_total = 0
cc_total = 0
have_jsonl = False
if session_id and cwd:
    encoded = '-' + cwd.lstrip('/').replace('/', '-')
    jsonl = os.path.expanduser(f'~/.claude/projects/{encoded}/{session_id}.jsonl')
    try:
        with open(jsonl, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                if entry.get('type') != 'assistant':
                    continue
                usage = entry.get('message', {}).get('usage', {}) or {}
                cb = usage.get('cache_creation', {}) or {}
                eph_5m += cb.get('ephemeral_5m_input_tokens', 0) or 0
                eph_1h += cb.get('ephemeral_1h_input_tokens', 0) or 0
                out_total += usage.get('output_tokens', 0) or 0
                in_total += usage.get('input_tokens', 0) or 0
                cr_total += usage.get('cache_read_input_tokens', 0) or 0
                cc_total += usage.get('cache_creation_input_tokens', 0) or 0
                have_jsonl = True
    except (FileNotFoundError, OSError):
        pass

if have_jsonl:
    out_tok = out_total
    cr = cr_total
    cc = cc_total
    in_tok = in_total

# Cache hit rate: reads / (reads + writes + uncached input)
denom = cr + cc + in_tok
hit_pct = round(100.0 * cr / denom) if denom > 0 else 0

print(m, dn, in_tok, out_tok, cr, cc, used_pct, ctx_total, fh, sd, fh_r, sd_r, dur, usd, eph_5m, eph_1h, hit_pct, sep='|')
")

# --- Helpers ---
fmt_tokens() {
  local n=${1:-0}
  awk "BEGIN {
    v = $n + 0
    if (v >= 1000000) printf \"%.1fM\", v/1000000
    else if (v >= 1000) printf \"%.1fK\", v/1000
    else printf \"%d\", v
  }"
}

fmt_duration() {
  local ms=${1:-0}
  local total_sec=$((ms / 1000))
  local hrs=$((total_sec / 3600))
  local mins=$(( (total_sec % 3600) / 60 ))
  local secs=$((total_sec % 60))
  if [ "$hrs" -gt 0 ]; then
    printf '%dh %dm' "$hrs" "$mins"
  elif [ "$mins" -gt 0 ]; then
    printf '%dm %ds' "$mins" "$secs"
  else
    printf '%ds' "$secs"
  fi
}

fmt_5h_reset() {
  local epoch=$1
  if [ -n "$epoch" ] && [ "$epoch" != "None" ] && [ "$epoch" != "" ]; then
    TZ="America/Chicago" date -d "@${epoch}" '+%-I:%M %P' 2>/dev/null || echo "?"
  else
    echo "?"
  fi
}

fmt_7d_reset() {
  local epoch=$1
  if [ -n "$epoch" ] && [ "$epoch" != "None" ] && [ "$epoch" != "" ]; then
    local day_name day_num suffix time_str
    day_name=$(TZ="America/Chicago" date -d "@${epoch}" '+%a' 2>/dev/null)
    day_num=$(TZ="America/Chicago" date -d "@${epoch}" '+%-d' 2>/dev/null)
    time_str=$(TZ="America/Chicago" date -d "@${epoch}" '+%-I:%M %P' 2>/dev/null)
    case "$day_num" in
      1|21|31) suffix="st" ;; 2|22) suffix="nd" ;; 3|23) suffix="rd" ;; *) suffix="th" ;;
    esac
    echo "${day_name} ${day_num}${suffix} ${time_str}"
  else
    echo "?"
  fi
}

fmt_cost() {
  local usd=${1:-0}
  awk "BEGIN { printf \"\044%.2f\", $usd + 0 }"
}

# Gradient progress bar: shifts dark-to-bright across filled portion
make_gradient_bar() {
  local pct=$1 width=10
  local gs_r gs_g gs_b ge_r ge_g ge_b
  IFS=';' read -r gs_r gs_g gs_b <<< "$GRAD_START_RGB"
  IFS=';' read -r ge_r ge_g ge_b <<< "$GRAD_END_RGB"
  local filled=0
  if [ -n "$pct" ] && [ "$pct" != "None" ] && [ "$pct" != "" ]; then
    filled=$(awk "BEGIN { v=int($pct * $width / 100 + 0.5); if(v>$width) v=$width; if(v<0) v=0; print v }")
  fi
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do
    if [ "$filled" -le 1 ]; then
      local t_r=$(( (gs_r + ge_r) / 2 )) t_g=$(( (gs_g + ge_g) / 2 )) t_b=$(( (gs_b + ge_b) / 2 ))
    else
      local t_r=$((gs_r + (ge_r - gs_r) * i / (filled-1)))
      local t_g=$((gs_g + (ge_g - gs_g) * i / (filled-1)))
      local t_b=$((gs_b + (ge_b - gs_b) * i / (filled-1)))
    fi
    bar+="\033[38;2;${t_r};${t_g};${t_b}m▰"
  done
  bar+="${GRAD_EMPTY}"
  for ((i=0; i<empty; i++)); do bar+="▱"; done
  printf '%b' "$bar"
}

# --- Format values ---
in_fmt=$(fmt_tokens "$in_tok")
out_fmt=$(fmt_tokens "$out_tok")
cache_read_fmt=$(fmt_tokens "$cache_read")
cache_write_fmt=$(fmt_tokens "$cache_create")
eph_5m_fmt=$(fmt_tokens "$eph_5m")
eph_1h_fmt=$(fmt_tokens "$eph_1h")
duration_fmt=$(fmt_duration "$duration_ms")
cost_fmt=$(fmt_cost "$cost_usd")
five_h_reset_fmt=$(fmt_5h_reset "$five_h_resets")
seven_d_reset_fmt=$(fmt_7d_reset "$seven_d_resets")

if [ -n "$ctx_used_pct" ] && [ "$ctx_used_pct" != "None" ] && [ "${ctx_total:-0}" -gt 0 ] 2>/dev/null; then
  ctx_used_raw=$(awk "BEGIN { printf \"%d\", $ctx_used_pct * $ctx_total / 100 }")
  ctx_used_fmt=$(fmt_tokens "$ctx_used_raw")
  ctx_total_fmt=$(fmt_tokens "$ctx_total")
  ctx_str="${ctx_used_fmt} / ${ctx_total_fmt}"
else
  ctx_str="-- / --"
  ctx_used_pct=""
fi

# ============================================================
# Palette — defaults: Tokyo Night (fallback when the repo
# exporter is unreachable); the eval overrides them with the
# live master theme from the wezterm repo.
# ============================================================
RST=$'\033[0m'

BG_L1=$'\033[48;2;36;40;59m'       # #24283b
BG_L2=$'\033[48;2;41;46;66m'       # #292e42
FG=$'\033[38;2;169;177;214m'       # #a9b1d6 — main fg (values)
DIM=$'\033[38;2;86;95;137m'        # #565f89 — labels, separators
ACCENT=$'\033[38;2;125;207;255m'   # #7dcfff — dir, model, key values
CLR_OK=$'\033[38;2;158;206;106m'   # #9ece6a green
CLR_WARN=$'\033[38;2;224;175;104m' # #e0af68 amber
CLR_CRIT=$'\033[38;2;247;118;142m' # #f7768e red
GRAD_START_RGB='61;89;161'         # #3d59a1
GRAD_END_RGB='122;162;247'         # #7aa2f7
GRAD_EMPTY=$'\033[38;2;52;59;88m'  # #343b58

if [ -n "$TERMINAL_REPO_DIR" ] && command -v lua >/dev/null 2>&1; then
  eval "$(lua "$TERMINAL_REPO_DIR/integrations/claude-code/theme-export.lua" --bash --sync 2>/dev/null)"
fi

# Context pressure color
ctx_int=0
if [ -n "$ctx_used_pct" ] && [ "$ctx_used_pct" != "None" ]; then
  ctx_int=$(printf '%.0f' "$ctx_used_pct")
  if [ "$ctx_int" -ge 90 ]; then
    CLR_CTX=$CLR_CRIT
  elif [ "$ctx_int" -ge 70 ]; then
    CLR_CTX=$CLR_WARN
  else
    CLR_CTX=$FG
  fi
else
  CLR_CTX=$DIM
fi

# Peak window: weekdays, 12:00–17:59 UTC (GMT noon–6pm)
utc_hour=$(TZ=UTC date +%-H)
utc_dow=$(TZ=UTC date +%u)   # 1=Mon … 7=Sun
is_peak=0
if [ "$utc_dow" -le 5 ] && [ "$utc_hour" -ge 12 ] && [ "$utc_hour" -lt 18 ]; then
  is_peak=1
fi

# Worst quota used (for peak+crit escalation)
worst_pct=0
for p in "$five_h_pct" "$seven_d_pct"; do
  [ -z "$p" ] || [ "$p" = "None" ] && continue
  pi=$(printf '%.0f' "$p")
  [ "$pi" -gt "$worst_pct" ] && worst_pct=$pi
done

if [ "$is_peak" = 1 ] && [ "$worst_pct" -ge 80 ]; then
  CLR_COST=$CLR_CRIT
elif [ "$is_peak" = 1 ]; then
  CLR_COST=$CLR_WARN
else
  CLR_COST=$CLR_OK
fi

# =============== LINE 1 ===============
# dir · model · in N  out N  cache N · ctx X/Y · $cost · duration
L1="${BG_L1} "
L1+="${ACCENT}${folder_icon} ${dir_name}"
L1+="${DIM}${DOT}"
L1+="${ACCENT}${model}"
L1+="${DIM}${DOT}"
L1+="${DIM}in ${FG}${in_fmt}  ${DIM}out ${FG}${out_fmt}  ${DIM}r ${FG}${cache_read_fmt}  ${DIM}w ${FG}${cache_write_fmt}  ${DIM}hit ${FG}${hit_pct}%"
L1+="${DIM}${DOT}"
L1+="${DIM}ctx ${CLR_CTX}${ctx_str}"
L1+="${DIM}${DOT}"
L1+="${CLR_COST}${cost_fmt} "
L1+="${RST}"

# =============== LINE 2 ===============
# 5m N · 1h N · 5h bar · 7d bar · duration
L2="${BG_L2} "
L2+="${DIM}5m ${FG}${eph_5m_fmt}  ${DIM}1h ${FG}${eph_1h_fmt}"
L2+="${DIM}${DOT}"

if [ -n "$five_h_pct" ] && [ "$five_h_pct" != "None" ] && [ "$five_h_pct" != "" ]; then
  five_int=$(printf '%.0f' "$five_h_pct")
  five_bar=$(make_gradient_bar "$five_h_pct")
  L2+=$(printf "${FG}5h %3d%%  " "$five_int")
  L2+="${five_bar}${BG_L2}  ${DIM}resets ${FG}${five_h_reset_fmt}"
else
  L2+="${FG}5h ${DIM}--%  ${GRAD_EMPTY}▱▱▱▱▱▱▱▱▱▱${BG_L2}"
fi

L2+="${DIM}${DOT}"

if [ -n "$seven_d_pct" ] && [ "$seven_d_pct" != "None" ] && [ "$seven_d_pct" != "" ]; then
  seven_int=$(printf '%.0f' "$seven_d_pct")
  seven_bar=$(make_gradient_bar "$seven_d_pct")
  L2+=$(printf "${FG}7d %3d%%  " "$seven_int")
  L2+="${seven_bar}${BG_L2}  ${DIM}resets ${FG}${seven_d_reset_fmt}"
else
  L2+="${FG}7d ${DIM}--%  ${GRAD_EMPTY}▱▱▱▱▱▱▱▱▱▱${BG_L2}"
fi

L2+="${DIM}${DOT}${DIM}${duration_fmt} ${RST}"

# --- Equalize line widths (pad shorter line's bg to match longer) ---
visible_len() {
  # strip ANSI escapes, then count chars (python handles multibyte correctly)
  printf '%b' "$1" | python3 -c "
import sys, re
s = sys.stdin.read()
s = re.sub(r'\x1b\[[0-9;]*m', '', s)
# strip trailing newline only
if s.endswith('\n'): s = s[:-1]
print(len(s))
"
}

l1_len=$(visible_len "$L1")
l2_len=$(visible_len "$L2")

if [ "$l1_len" -gt "$l2_len" ]; then
  pad=$((l1_len - l2_len))
  pad_str=$(printf '%*s' "$pad" '')
  L2="${L2%${RST}}${BG_L2}${pad_str}${RST}"
elif [ "$l2_len" -gt "$l1_len" ]; then
  pad=$((l2_len - l1_len))
  pad_str=$(printf '%*s' "$pad" '')
  L1="${L1%${RST}}${BG_L1}${pad_str}${RST}"
fi

# --- Output ---
echo -e "${L1}"
echo -e "${L2}"
