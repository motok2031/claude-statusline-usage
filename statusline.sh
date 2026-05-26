#!/bin/bash
# claude-statusline-usage
# A compact, info-dense status line for Claude Code.
# https://github.com/motok2031/claude-statusline-usage

# ============================================================
# Config — tweak these to taste
# ============================================================

# Bar width in cells (each limit bar). Smaller = more compact.
BAR_WIDTH=${CSU_BAR_WIDTH:-8}

# Path to the Python 3 interpreter. Default `python3` works on most systems.
# pyenv users: set this to the real binary (e.g. /usr/bin/python3 or
# ~/.pyenv/versions/X.Y.Z/bin/python3) to skip the ~60ms shim overhead per call.
PYTHON=${CSU_PYTHON:-python3}

# Context-usage health thresholds (percent of context window used).
# Below WARN  → green
# WARN..HOT-1 → orange
# HOT..CRIT-1 → orange-red
# >= CRIT     → red
HEALTH_WARN=${CSU_HEALTH_WARN:-20}
HEALTH_HOT=${CSU_HEALTH_HOT:-33}
HEALTH_CRIT=${CSU_HEALTH_CRIT:-40}

# Colors (256-color ANSI codes). Override via env if your terminal palette differs.
COLOR_MODEL=${CSU_COLOR_MODEL:-252}     # model name (light gray)
COLOR_TIME=${CSU_COLOR_TIME:-33}        # time-elapsed segment / reset timer (yellow, 16-color)
COLOR_USAGE=${CSU_COLOR_USAGE:-94}      # usage-percent segment / token counts (bright blue, 16-color)
COLOR_EMPTY=${CSU_COLOR_EMPTY:-245}     # unfilled bar cells (mid gray)
COLOR_OK=${CSU_COLOR_OK:-71}            # ctx% when healthy   (mid green)
COLOR_WARN=${CSU_COLOR_WARN:-208}       # ctx% when warning   (orange)
COLOR_HOT=${CSU_COLOR_HOT:-202}         # ctx% when hot       (orange-red)
COLOR_CRIT=${CSU_COLOR_CRIT:-196}       # ctx% when critical  (red)

# ============================================================
# Implementation
# ============================================================

NOW=$(date +%s)

# Parse the stdin JSON + scan the session transcript for cumulative in/out
# tokens — all in a single Python process. Replaces ~11 jq + sed/tr/grep
# subprocess spawns from the previous implementation.
IFS=$'\t' read -r MODEL CTX_USED CTX_MAX CTX_PCT F_PCT F_RESET W_PCT W_RESET TI TO < <(
"$PYTHON" -c '
import json, os, re, sys
d = json.load(sys.stdin)

def g(o, *ks):
    for k in ks:
        if not isinstance(o, dict): return None
        o = o.get(k)
        if o is None: return None
    return o

raw = g(d, "model", "display_name") or g(d, "model", "id") or "?"
mid = g(d, "model", "id") or ""
model = re.sub(r"\s*\(.*", "", raw).lower().replace(" ", "-")
if "1m" in (raw + " " + mid).lower():
    model += "[1m]"

trans = g(d, "transcript_path") or ""
ti = to = 0
if trans and os.path.isfile(trans):
    with open(trans) as fh:
        for line in fh:
            try: o = json.loads(line)
            except Exception: continue
            if o.get("type") != "assistant": continue
            u = (o.get("message") or {}).get("usage")
            if not u: continue
            ti += (u.get("input_tokens") or 0)
            ti += (u.get("cache_creation_input_tokens") or 0)
            ti += (u.get("cache_read_input_tokens") or 0)
            to += (u.get("output_tokens") or 0)

s = lambda v: "" if v is None else str(v)
print("\t".join(s(x) for x in [
    model,
    g(d, "context_window", "total_input_tokens") or 0,
    g(d, "context_window", "context_window_size") or 0,
    g(d, "context_window", "used_percentage") or 0,
    g(d, "rate_limits", "five_hour", "used_percentage"),
    g(d, "rate_limits", "five_hour", "resets_at"),
    g(d, "rate_limits", "seven_day", "used_percentage"),
    g(d, "rate_limits", "seven_day", "resets_at"),
    ti, to,
]))
'
)

# --- ANSI helpers ---
R=$'\e[0m'
DIM=$'\e[90m'
fg256() { printf '\e[38;5;%sm' "$1"; }
fg16()  { printf '\e[%sm' "$1"; }

MODEL_C=$(fg256 "$COLOR_MODEL")
TIME_C=$(fg16  "$COLOR_TIME")
USAGE_C=$(fg16 "$COLOR_USAGE")
EMPTY_C=$(fg256 "$COLOR_EMPTY")
C_OK=$(fg256   "$COLOR_OK")
C_WARN=$(fg256 "$COLOR_WARN")
C_HOT=$(fg256  "$COLOR_HOT")
C_CRIT=$(fg256 "$COLOR_CRIT")

fmt_tokens() {
  local n=$(( ($1 + 500) / 1000 ))
  if [ "$n" -ge 1000 ]; then
    awk -v x="$n" 'BEGIN{printf "%.1fm", x/1000}'
  else
    echo "${n}k"
  fi
}

fmt_dur() {
  local s=$1
  [ "$s" -le 0 ] 2>/dev/null && { echo "0m"; return; }
  local d=$((s/86400)) h=$(((s%86400)/3600)) m=$(((s%3600)/60))
  if   [ "$d" -gt 0 ]; then echo "${d}d${h}h"
  elif [ "$h" -gt 0 ]; then echo "${h}h${m}m"
  else                       echo "${m}m"
  fi
}

# Dual-stack bar: overlays time-elapsed% and usage% on one row.
# Whichever percent is smaller is drawn first (so its color "wins" visually
# in the overlap region); empty cells fill the rest.
bar_dual() {
  local t=$1 u=$2 w=$BAR_WIDTH
  local ts=$(( (t * w + 50) / 100 )) us=$(( (u * w + 50) / 100 ))
  [ "$ts" -gt "$w" ] && ts=$w
  [ "$us" -gt "$w" ] && us=$w
  if [ "$ts" -eq "$us" ] && [ "$t" -ne "$u" ]; then
    if   [ "$t" -gt "$u" ] && [ "$ts" -lt "$w" ]; then ts=$((ts+1))
    elif [ "$u" -gt "$t" ] && [ "$us" -lt "$w" ]; then us=$((us+1))
    fi
  fi
  local fn fc sn sc
  if [ "$ts" -le "$us" ]; then
    fn=$ts; fc=$TIME_C;  sn=$us; sc=$USAGE_C
  else
    fn=$us; fc=$USAGE_C; sn=$ts; sc=$TIME_C
  fi
  local out="" i
  for ((i=0;  i<fn; i++)); do out="${out}${fc}━"; done
  for ((i=fn; i<sn; i++)); do out="${out}${sc}━"; done
  for ((i=sn; i<w;  i++)); do out="${out}${EMPTY_C}─"; done
  printf '%s%b' "$out" "$R"
}

render_limit() {
  local label=$1 pct=$2 reset_at=$3 window=$4
  [ -z "$pct" ] && return
  local upct
  upct=$(printf '%.0f' "$pct")
  local tpct=0 tleft="--"
  if [ -n "$reset_at" ] && [ "$reset_at" -gt 0 ] 2>/dev/null; then
    local left=$(( reset_at - NOW ))
    [ "$left" -lt 0 ] && left=0
    local elapsed=$(( window - left ))
    [ "$elapsed" -lt 0 ] && elapsed=0
    tpct=$(( elapsed * 100 / window ))
    tleft=$(fmt_dur "$left")
  fi
  printf '%b%s%b %s %b%s%%%b %b%s%b' \
    "$DIM" "$label" "$R" \
    "$(bar_dual "$tpct" "$upct")" \
    "$USAGE_C" "$upct" "$R" \
    "$TIME_C" "$tleft" "$R"
}

CTX_PCT_I=$(printf '%.0f' "$CTX_PCT" 2>/dev/null || echo 0)
if   [ "$CTX_PCT_I" -ge "$HEALTH_CRIT" ]; then HEALTH=$C_CRIT
elif [ "$CTX_PCT_I" -ge "$HEALTH_HOT"  ]; then HEALTH=$C_HOT
elif [ "$CTX_PCT_I" -ge "$HEALTH_WARN" ]; then HEALTH=$C_WARN
else                                           HEALTH=$C_OK
fi
CTX_STR=""
if [ "$CTX_MAX" -gt 0 ] 2>/dev/null; then
  CTX_STR="$(fmt_tokens "$CTX_USED")/$(fmt_tokens "$CTX_MAX")(${HEALTH}${CTX_PCT_I}%${R})"
fi

OUT="${MODEL_C}${MODEL}${R}  ${CTX_STR}  ${DIM}in${R} $(fmt_tokens "$TI") ${DIM}out${R} $(fmt_tokens "$TO")"
[ -n "$F_PCT" ] && OUT="${OUT}  $(render_limit "5h" "$F_PCT" "$F_RESET" 18000)"
[ -n "$W_PCT" ] && OUT="${OUT}  $(render_limit "7d" "$W_PCT" "$W_RESET" 604800)"
printf '%s\n' "$OUT"
