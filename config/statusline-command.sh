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
  < <(echo "$input" | python3 -c "
import sys, json
d = json.load(sys.stdin)
m = d.get('model', {}).get('display_name', '?')
cwd = d.get('cwd', '')
dn = cwd.rsplit('/', 1)[-1] if cwd else '~'

cw = d.get('context_window', {})
cu = cw.get('current_usage', {})
in_tok  = cu.get('input_tokens', 0) + cu.get('cache_read_input_tokens', 0) + cu.get('cache_creation_input_tokens', 0)
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

print(m, dn, in_tok, out_tok, cr, cc, used_pct, ctx_total, fh, sd, fh_r, sd_r, dur, usd, sep='|')
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
    TZ="America/Chicago" date -d "@${epoch}" '+%-I:%M %P' 2>/dev/null || echo "?" # <-- edit per machine: timezone (America/Chicago)
  else
    echo "?"
  fi
}

fmt_7d_reset() {
  local epoch=$1
  if [ -n "$epoch" ] && [ "$epoch" != "None" ] && [ "$epoch" != "" ]; then
    local day_name day_num suffix time_str
    day_name=$(TZ="America/Chicago" date -d "@${epoch}" '+%a' 2>/dev/null) # <-- edit per machine: timezone
    day_num=$(TZ="America/Chicago" date -d "@${epoch}" '+%-d' 2>/dev/null) # <-- edit per machine: timezone
    time_str=$(TZ="America/Chicago" date -d "@${epoch}" '+%-I:%M %P' 2>/dev/null) # <-- edit per machine: timezone
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
  local filled=0
  if [ -n "$pct" ] && [ "$pct" != "None" ] && [ "$pct" != "" ]; then
    filled=$(awk "BEGIN { v=int($pct * $width / 100 + 0.5); if(v>$width) v=$width; if(v<0) v=0; print v }")
  fi
  local empty=$((width - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do
    if [ "$filled" -le 1 ]; then
      local t_r=92 t_g=126 t_b=204
    else
      local t_r=$((61 + (122-61) * i / (filled-1)))
      local t_g=$((89 + (162-89) * i / (filled-1)))
      local t_b=$((161 + (247-161) * i / (filled-1)))
    fi
    bar+="\033[38;2;${t_r};${t_g};${t_b}m▰"
  done
  bar+="\033[38;2;52;59;88m"
  for ((i=0; i<empty; i++)); do bar+="▱"; done
  printf '%b' "$bar"
}

# --- Format values ---
in_fmt=$(fmt_tokens "$in_tok")
out_fmt=$(fmt_tokens "$out_tok")
cache_total=$((cache_read + cache_create))
cache_fmt=$(fmt_tokens "$cache_total")
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
# Palette — muted base, one accent, state-colors for cost + ctx
# ============================================================
RST=$'\033[0m'

BG_L1=$'\033[48;2;36;40;59m'      # #24283b
BG_L2=$'\033[48;2;41;46;66m'      # #292e42

FG=$'\033[38;2;169;177;214m'      # #a9b1d6 — main fg (values)
DIM=$'\033[38;2;86;95;137m'       # #565f89 — labels, separators
ACCENT=$'\033[38;2;125;207;255m'  # #7dcfff — single accent (dir, model, key values)

# State colors — used for cost (peak) and ctx (pressure)
CLR_OK=$'\033[38;2;158;206;106m'   # #9ece6a green
CLR_WARN=$'\033[38;2;224;175;104m' # #e0af68 amber
CLR_CRIT=$'\033[38;2;247;118;142m' # #f7768e red

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
L1+="${DIM}in ${FG}${in_fmt}  ${DIM}out ${FG}${out_fmt}  ${DIM}cache ${FG}${cache_fmt}"
L1+="${DIM}${DOT}"
L1+="${DIM}ctx ${CLR_CTX}${ctx_str}"
L1+="${DIM}${DOT}"
L1+="${CLR_COST}${cost_fmt} "
L1+="${RST}"

# =============== LINE 2 ===============
# 5h N%  bar  resets T · 7d N%  bar  resets T
L2="${BG_L2} "

if [ -n "$five_h_pct" ] && [ "$five_h_pct" != "None" ] && [ "$five_h_pct" != "" ]; then
  five_int=$(printf '%.0f' "$five_h_pct")
  five_bar=$(make_gradient_bar "$five_h_pct")
  L2+=$(printf "${FG}5h %3d%%  " "$five_int")
  L2+="${five_bar}${BG_L2}  ${DIM}resets ${FG}${five_h_reset_fmt}"
else
  L2+="${FG}5h ${DIM}--%  \033[38;2;52;59;88m▱▱▱▱▱▱▱▱▱▱${BG_L2}"
fi

L2+="${DIM}${DOT}"

if [ -n "$seven_d_pct" ] && [ "$seven_d_pct" != "None" ] && [ "$seven_d_pct" != "" ]; then
  seven_int=$(printf '%.0f' "$seven_d_pct")
  seven_bar=$(make_gradient_bar "$seven_d_pct")
  L2+=$(printf "${FG}7d %3d%%  " "$seven_int")
  L2+="${seven_bar}${BG_L2}  ${DIM}resets ${FG}${seven_d_reset_fmt}"
else
  L2+="${FG}7d ${DIM}--%  \033[38;2;52;59;88m▱▱▱▱▱▱▱▱▱▱${BG_L2}"
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
