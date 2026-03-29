#!/bin/bash
set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# Escribir el script de status line
cat > "$SCRIPT" << 'EOF'
#!/bin/bash
input=$(cat)
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hr=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
agent_name=$(echo "$input" | jq -r '.agent.name // empty')

RED='\033[31m'; YELLOW='\033[33m'; GREEN='\033[32m'
CYAN='\033[36m'; BLUE='\033[34m'; DIM='\033[2m'
BOLD='\033[1m'; RESET='\033[0m'
SEP="${DIM} │ ${RESET}"

color_pct() {
  [ "$1" -ge 80 ] && echo "$RED" || { [ "$1" -ge 50 ] && echo "$YELLOW" || echo "$GREEN"; }
}
bar() {
  local filled=$(( $1 * 8 / 100 )) b=""
  local empty=$(( 8 - filled ))
  for ((i=0;i<filled;i++)); do b+="█"; done
  for ((i=0;i<empty;i++)); do b+="░"; done
  echo "$b"
}

parts=()
[ -n "$vim_mode" ]   && parts+=("${YELLOW}${vim_mode}${RESET}")
[ -n "$agent_name" ] && parts+=("${CYAN}⚙ ${agent_name}${RESET}")
parts+=("${BOLD}${BLUE}${model}${RESET}")

if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used"); col=$(color_pct "$pct"); b=$(bar "$pct")
  parts+=("${col}${b} ${pct}%${RESET}")
fi
if [ -n "$five_hr" ]; then
  fpct=$(printf '%.0f' "$five_hr"); col=$(color_pct "$fpct"); b=$(bar "$fpct")
  parts+=("${DIM}5h${RESET} ${col}${b} ${fpct}%${RESET}")
fi
if [ -n "$seven_day" ]; then
  wpct=$(printf '%.0f' "$seven_day"); col=$(color_pct "$wpct"); b=$(bar "$wpct")
  parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET}")
fi

out=""
for i in "${!parts[@]}"; do [ "$i" -gt 0 ] && out+="$SEP"; out+="${parts[$i]}"; done
printf '%b' "$out"
EOF

chmod +x "$SCRIPT"

# Actualizar settings.json conservando configuración existente
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
  tmp=$(mktemp)
  jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline-command.sh"}}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
  # Si no existe o no hay jq, crear mínimo
  cat > "$SETTINGS" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
EOF
fi

echo "✓ Instalado. Reinicia Claude Code para ver la status line."
