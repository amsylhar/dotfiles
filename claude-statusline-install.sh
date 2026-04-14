#!/bin/bash
# Install Claude Code status line with:
#   - Context window usage
#   - 5h rate limit + countdown to reset + pace delta
#   - 7d rate limit + weekly cycle pace delta (resets every Thursday 17:00)
#   - Model name, vim mode, agent name
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

model=$(echo "$input"    | jq -r '.model.display_name // "unknown"')
used=$(echo "$input"     | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
five_hr=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input"| jq -r '.rate_limits.seven_day.used_percentage // empty')
agent_name=$(echo "$input"| jq -r '.agent.name // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')

# Cache 7d value for claude-credits tool
[ -n "$seven_day" ] && printf '%s\n' "$seven_day" > "${HOME}/.claude/credits-cache" 2>/dev/null || true

# ── Weekly cycle position (Thu 17:00 → Thu 17:00) ────────────────────────────
_dow=$(date +%u); _h=$(date +%-H); _m=$(date +%-M)
_now_s=$(( (_dow-1)*86400 + _h*3600 + _m*60 ))
_rst_s=$(( 3*86400 + 17*3600 ))
_tot_s=$(( 7*86400 ))
[ "$_now_s" -ge "$_rst_s" ] && _elp_s=$(( _now_s - _rst_s )) \
                              || _elp_s=$(( _tot_s - _rst_s + _now_s ))
CICLO_PCT=$(( _elp_s * 100 / _tot_s ))
_rem_s=$(( _tot_s - _elp_s ))
_rem_d=$(( _rem_s / 86400 ))
_rem_h=$(( (_rem_s % 86400) / 3600 ))
[ "$_rem_d" -gt 0 ] && CICLO_REM="${_rem_d}d" || CICLO_REM="${_rem_h}h"

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
  reset_time=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
  if [ -n "$reset_time" ]; then
    _now=$(date +%s)
    _rst=$(echo "$reset_time" | cut -c1-10)
    _diff=$(( _rst - _now ))
    if [ "$_diff" -gt 0 ]; then
      _rh=$(( _diff / 3600 )); _rm=$(( (_diff % 3600) / 60 ))
      [ "$_rh" -gt 0 ] && _rfmt="${_rh}h ${_rm}m" || _rfmt="${_rm}m"
      # Pace delta for 5h window
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
  _delta=$(( wpct - CICLO_PCT ))
  if [ "$_delta" -le 5 ] && [ "$_delta" -ge -100 ]; then _dcol="$GREEN"
  elif [ "$_delta" -le 15 ]; then _dcol="$YELLOW"
  else _dcol="$RED"; fi
  [ "$_delta" -ge 0 ] && _dsign="+" || _dsign=""
    parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET} ${DIM}${CICLO_REM} (${RESET}${_dcol}${_dsign}${_delta}%${RESET}${DIM})${RESET}")
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
