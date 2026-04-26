#!/bin/bash
# Install Claude Code status line with:
#   - Context window usage
#   - 5h rate limit + countdown to reset + pace delta
#   - 7d rate limit + dynamic cycle from API + pace delta
#   - Model name, vim mode, agent name, worktree
#   - Writes credits cache for claude-credits tool
set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

cat > "$SCRIPT" << 'EOF'
#!/bin/bash
# Claude Code status line

input=$(cat)

mapfile -t _f < <(printf '%s' "$input" | jq -r '
  (.model.display_name // "unknown"),
  ((.context_window.used_percentage // "") | tostring),
  (.vim.mode // ""),
  (.agent.name // ""),
  (.worktree.name // ""),
  ((.rate_limits.five_hour.used_percentage // "") | tostring),
  ((.rate_limits.five_hour.resets_at // "") | tostring),
  ((.rate_limits.seven_day.used_percentage // "") | tostring),
  ((.rate_limits.seven_day.resets_at // "") | tostring)
')
model="${_f[0]}"
used="${_f[1]}"
vim_mode="${_f[2]}"
agent_name="${_f[3]}"
worktree="${_f[4]}"
five_hr="${_f[5]}"
five_hr_reset="${_f[6]}"
seven_day="${_f[7]}"
seven_day_reset="${_f[8]}"

[ -n "$seven_day" ] && printf '%s %s\n' "$seven_day" "${seven_day_reset}" > "${HOME}/.claude/credits-cache" 2>/dev/null || true

# ── Posición en el ciclo 7d usando resets_at real de la API ─────────────────
CICLO_PCT=""
CICLO_REM=""
if [ -n "$seven_day_reset" ]; then
  _now=$(date +%s)
  _diff=$(( seven_day_reset - _now ))
  _tot_s=$(( 7*86400 ))
  if [ "$_diff" -gt 0 ]; then
    _elp_s=$(( _tot_s - _diff ))
    CICLO_PCT=$(( _elp_s * 100 / _tot_s ))
    _rem_d=$(( _diff / 86400 ))
    _rem_h=$(( (_diff % 86400) / 3600 ))
    if [ "$_rem_d" -gt 0 ] && [ "$_rem_h" -gt 0 ]; then
      CICLO_REM="${_rem_d}d ${_rem_h}h"
    elif [ "$_rem_d" -gt 0 ]; then
      CICLO_REM="${_rem_d}d"
    else
      CICLO_REM="${_rem_h}h"
    fi
  else
    CICLO_PCT=100
    CICLO_REM="0h"
  fi
fi

RED='\033[31m'; YELLOW='\033[33m'; GREEN='\033[32m'
CYAN='\033[36m'; BLUE='\033[34m'; DIM='\033[2m'
BOLD='\033[1m'; RESET='\033[0m'
SEP="${DIM} │ ${RESET}"

color_pct() {
  [ "$1" -ge 80 ] && echo "$RED" || { [ "$1" -ge 50 ] && echo "$YELLOW" || echo "$GREEN"; }
}
bar() {
  local filled=$(( $1 * 8 / 100 )) empty=$(( 8 - $1 * 8 / 100 )) b=""
  for ((i=0;i<filled;i++)); do b+="█"; done
  for ((i=0;i<empty;i++));  do b+="░"; done
  echo "$b"
}

parts=()
[ -n "$vim_mode" ]   && parts+=("${YELLOW}${vim_mode}${RESET}")
[ -n "$agent_name" ] && parts+=("${CYAN}⚙ ${agent_name}${RESET}")
[ -n "$worktree" ]   && parts+=("${DIM}⎇ ${worktree}${RESET}")
parts+=("${BOLD}${BLUE}${model}${RESET}")

if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used"); col=$(color_pct "$pct"); b=$(bar "$pct")
  parts+=("${col}${b} ${pct}%${RESET}")
fi

if [ -n "$five_hr" ]; then
  fpct=$(printf '%.0f' "$five_hr"); col=$(color_pct "$fpct"); b=$(bar "$fpct")
  if [ -n "$five_hr_reset" ]; then
    _now=$(date +%s)
    _diff=$(( five_hr_reset - _now ))
    if [ "$_diff" -gt 0 ]; then
      _rh=$(( _diff / 3600 )); _rm=$(( (_diff % 3600) / 60 ))
      [ "$_rh" -gt 0 ] && _rfmt="${_rh}h ${_rm}m" || _rfmt="${_rm}m"
      _5h_elapsed=$(( 5*3600 - _diff ))
      _5h_epct=$(( _5h_elapsed * 100 / (5*3600) ))
      _5h_delta=$(( fpct - _5h_epct ))
      if [ "$_5h_delta" -le 5 ] && [ "$_5h_delta" -ge -100 ]; then _5dcol="$GREEN"
      elif [ "$_5h_delta" -le 15 ]; then _5dcol="$YELLOW"
      else _5dcol="$RED"; fi
      [ "$_5h_delta" -ge 0 ] && _5dsign="+" || _5dsign=""
      parts+=("${DIM}5h${RESET} ${col}${b} ${fpct}%${RESET} ${DIM}${_rfmt} (${RESET}${_5dcol}${_5dsign}${_5h_delta}%${RESET}${DIM})${RESET}")
    else
      parts+=("${DIM}5h${RESET} ${col}${b} ${fpct}%${RESET} ${DIM}~0m${RESET}")
    fi
  else
    parts+=("${DIM}5h${RESET} ${col}${b} ${fpct}%${RESET}")
  fi
fi

if [ -n "$seven_day" ]; then
  wpct=$(printf '%.0f' "$seven_day"); col=$(color_pct "$wpct"); b=$(bar "$wpct")
  if [ -n "$CICLO_PCT" ]; then
    _delta=$(( wpct - CICLO_PCT ))
    if [ "$_delta" -le 5 ] && [ "$_delta" -ge -100 ]; then _dcol="$GREEN"
    elif [ "$_delta" -le 15 ]; then _dcol="$YELLOW"
    else _dcol="$RED"; fi
    [ "$_delta" -ge 0 ] && _dsign="+" || _dsign=""
    parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET} ${DIM}${CICLO_REM} (${RESET}${_dcol}${_dsign}${_delta}%${RESET}${DIM})${RESET}")
  else
    parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET}")
  fi
fi

out=""
for i in "${!parts[@]}"; do [ "$i" -gt 0 ] && out+="$SEP"; out+="${parts[$i]}"; done
printf '%b' "$out"
EOF

chmod +x "$SCRIPT"

# Update settings.json
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
  tmp=$(mktemp)
  jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}}' \
    "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
  cat > "$SETTINGS" << 'EOFS'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
EOFS
fi

echo "✓ Status line installed. Restart Claude Code to activate."
echo ""
echo "Optional: install claude-credits for detailed weekly usage check:"
echo "  sudo cp claude-credits /usr/local/bin/ && sudo chmod +x /usr/local/bin/claude-credits"
