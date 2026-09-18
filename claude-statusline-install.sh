#!/bin/bash
# Install Claude Code status line with:
#   - Context window usage
#   - 5h rate limit + countdown to reset + pace delta
#   - 7d rate limit + dynamic cycle from API + pace delta
#   - Model name, vim mode, agent name, worktree
#   - Writes credits cache for claude-credits tool
#
# Run with:
#   curl -fsSL https://raw.githubusercontent.com/amsylhar/dotfiles/master/claude-statusline-install.sh | bash
set -e

RAW_BASE="https://raw.githubusercontent.com/amsylhar/dotfiles/master"
CLAUDE_DIR="$HOME/.claude"
SCRIPT="$CLAUDE_DIR/statusline-command.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# ── jq ────────────────────────────────────────────────────────────────────────
# The status line parses Claude Code's JSON with jq. When it is missing, install
# it: Homebrew if the user already has it, otherwise a checksum-verified static
# binary under ~/.claude/bin (no root needed, removed by deleting that folder).
JQ_VERSION="1.8.1"
JQ_BIN="$CLAUDE_DIR/bin/jq"

jq_asset() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=macos ;;
    Linux)  os=linux ;;
    *)      return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch=amd64 ;;
    arm64|aarch64) arch=arm64 ;;
    *)             return 1 ;;
  esac
  printf 'jq-%s-%s' "$os" "$arch"
}

# Official checksums from https://github.com/jqlang/jq/releases (sha256sum.txt)
jq_sha256() {
  case "$1" in
    jq-linux-amd64) echo "020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d" ;;
    jq-linux-arm64) echo "6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4" ;;
    jq-macos-amd64) echo "e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f" ;;
    jq-macos-arm64) echo "a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603" ;;
    *)              return 1 ;;
  esac
}

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else return 1
  fi
}

download_jq() {
  local asset want url tmp got
  asset=$(jq_asset) || { echo "  unsupported platform: $(uname -s) $(uname -m)" >&2; return 1; }
  want=$(jq_sha256 "$asset") || return 1
  url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${asset}"
  tmp=$(mktemp) || return 1
  echo "  downloading $asset (jq $JQ_VERSION)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$url" || { rm -f "$tmp"; return 1; }
  else
    echo "  neither curl nor wget is available" >&2; rm -f "$tmp"; return 1
  fi
  got=$(file_sha256 "$tmp") || {
    echo "  no sha256sum/shasum available to verify the download" >&2; rm -f "$tmp"; return 1; }
  if [ "$got" != "$want" ]; then
    echo "  checksum mismatch, discarding the download" >&2
    echo "    expected $want" >&2
    echo "    got      $got" >&2
    rm -f "$tmp"; return 1
  fi
  mkdir -p "$(dirname "$JQ_BIN")"
  mv "$tmp" "$JQ_BIN" && chmod 755 "$JQ_BIN"
}

if command -v jq >/dev/null 2>&1; then
  JQ=$(command -v jq)
elif [ -x "$JQ_BIN" ]; then
  JQ="$JQ_BIN"
  echo "✓ using jq previously installed at $JQ_BIN"
else
  echo "jq is required by the status line and was not found; installing it..."
  if command -v brew >/dev/null 2>&1 && brew install jq >/dev/null 2>&1 \
     && command -v jq >/dev/null 2>&1; then
    JQ=$(command -v jq)
    echo "✓ jq installed with Homebrew"
  elif download_jq; then
    JQ="$JQ_BIN"
    echo "✓ jq $JQ_VERSION installed at $JQ_BIN"
  else
    echo "✗ could not install jq automatically." >&2
    echo "  Install it by hand and run this again:" >&2
    echo "    macOS: brew install jq       ·  Debian/Ubuntu: sudo apt install jq" >&2
    echo "    Fedora: sudo dnf install jq  ·  Arch: sudo pacman -S jq" >&2
    exit 1
  fi
fi

# Never overwrite a settings.json we cannot parse: it holds permissions, hooks,
# mcpServers and everything else the user configured.
if [ -f "$SETTINGS" ] && ! "$JQ" empty "$SETTINGS" >/dev/null 2>&1; then
  echo "✗ $SETTINGS exists but is not valid JSON; refusing to touch it." >&2
  echo "  Fix or move that file, then run this installer again." >&2
  exit 1
fi

SCRIPT_TMP=$(mktemp)
cat > "$SCRIPT_TMP" << 'EOF'
#!/bin/bash
# Claude Code status line
# Kept compatible with bash 3.2 (the /bin/bash macOS still ships).

# jq lookup: PATH first, then the copy the installer may have dropped in
# ~/.claude/bin. Without it there is nothing to parse, so print nothing.
JQ=$(command -v jq 2>/dev/null || true)
if [ -z "$JQ" ] && [ -x "$HOME/.claude/bin/jq" ]; then JQ="$HOME/.claude/bin/jq"; fi
[ -n "$JQ" ] || exit 0

input=$(cat)

# One read per field instead of mapfile, which needs bash 4+.
{
  read -r model
  read -r used
  read -r vim_mode
  read -r agent_name
  read -r worktree
  read -r five_hr
  read -r five_hr_reset
  read -r seven_day
  read -r seven_day_reset
} < <(printf '%s' "$input" | "$JQ" -r '
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

# resets_at is expected to be a unix epoch; accept an ISO-8601 timestamp too and
# print nothing when it is neither, so arithmetic below never sees garbage.
to_epoch() {
  case "$1" in
    '') return 0 ;;
    *[!0-9]*) ;;
    *) printf '%s' "$1"; return 0 ;;
  esac
  date -d "$1" +%s 2>/dev/null && return 0
  local _s=${1%%.*}; _s=${_s%Z}
  date -j -f '%Y-%m-%dT%H:%M:%S' "$_s" +%s 2>/dev/null || true
}

# Round "43.6" → 44 without printf %f, which parses decimals per LC_NUMERIC
# (in comma-decimal locales it warns and truncates). Accepts "." and ",".
round_pct() {
  local v=${1//,/.} int frac
  int=${v%%.*}
  case $int in ''|*[!0-9]*) printf '0'; return 0 ;; esac
  frac=${v#*.}
  if [[ $v == *.* ]] && [[ ${frac:0:1} == [5-9] ]]; then int=$(( int + 1 )); fi
  printf '%s' "$int"
}

five_hr_reset=$(to_epoch "$five_hr_reset")
seven_day_reset=$(to_epoch "$seven_day_reset")

if [ -n "$seven_day" ]; then
  mkdir -p "${HOME}/.claude" 2>/dev/null || true
  printf '%s %s\n' "$seven_day" "$seven_day_reset" > "${HOME}/.claude/credits-cache" 2>/dev/null || true
fi

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

# Real escapes, so the final printf can use %s and never reinterpret
# backslashes coming from a model name, agent name or worktree path.
RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'
CYAN=$'\033[36m'; BLUE=$'\033[34m'; DIM=$'\033[2m'
BOLD=$'\033[1m'; RESET=$'\033[0m'
SEP="${DIM} │ ${RESET}"

# Thresholds, in one place: usage colour and how far ahead of the cycle the
# consumption may run before the pace delta stops being green.
USAGE_WARN=50; USAGE_CRIT=80
PACE_OK=5;     PACE_WARN=15

color_pct() {
  [ "$1" -ge "$USAGE_CRIT" ] && printf '%s' "$RED" \
    || { [ "$1" -ge "$USAGE_WARN" ] && printf '%s' "$YELLOW" || printf '%s' "$GREEN"; }
}
bar() {
  local pct=$1 filled empty b="" i
  [ "$pct" -lt 0 ] && pct=0
  [ "$pct" -gt 100 ] && pct=100
  filled=$(( pct * 8 / 100 )); empty=$(( 8 - filled ))
  for ((i=0;i<filled;i++)); do b+="█"; done
  for ((i=0;i<empty;i++));  do b+="░"; done
  printf '%s' "$b"
}
delta_color() {
  if [ "$1" -le "$PACE_OK" ]; then printf '%s' "$GREEN"
  elif [ "$1" -le "$PACE_WARN" ]; then printf '%s' "$YELLOW"
  else printf '%s' "$RED"; fi
}

parts=()
[ -n "$vim_mode" ]   && parts+=("${YELLOW}${vim_mode}${RESET}")
[ -n "$agent_name" ] && parts+=("${CYAN}⚙ ${agent_name}${RESET}")
[ -n "$worktree" ]   && parts+=("${DIM}⎇ ${worktree}${RESET}")
parts+=("${BOLD}${BLUE}${model}${RESET}")

if [ -n "$used" ]; then
  pct=$(round_pct "$used"); col=$(color_pct "$pct"); b=$(bar "$pct")
  parts+=("${col}${b} ${pct}%${RESET}")
fi

if [ -n "$five_hr" ]; then
  fpct=$(round_pct "$five_hr"); col=$(color_pct "$fpct"); b=$(bar "$fpct")
  if [ -n "$five_hr_reset" ]; then
    _now=$(date +%s)
    _diff=$(( five_hr_reset - _now ))
    if [ "$_diff" -gt 0 ]; then
      _rh=$(( _diff / 3600 )); _rm=$(( (_diff % 3600) / 60 ))
      [ "$_rh" -gt 0 ] && _rfmt="${_rh}h ${_rm}m" || _rfmt="${_rm}m"
      _5h_elapsed=$(( 5*3600 - _diff ))
      _5h_epct=$(( _5h_elapsed * 100 / (5*3600) ))
      _5h_delta=$(( fpct - _5h_epct ))
      _5dcol=$(delta_color "$_5h_delta")
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
  wpct=$(round_pct "$seven_day"); col=$(color_pct "$wpct"); b=$(bar "$wpct")
  if [ -n "$CICLO_PCT" ]; then
    _delta=$(( wpct - CICLO_PCT ))
    _dcol=$(delta_color "$_delta")
    [ "$_delta" -ge 0 ] && _dsign="+" || _dsign=""
    parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET} ${DIM}${CICLO_REM} (${RESET}${_dcol}${_dsign}${_delta}%${RESET}${DIM})${RESET}")
  else
    parts+=("${DIM}7d${RESET} ${col}${b} ${wpct}%${RESET}")
  fi
fi

out=""
for i in "${!parts[@]}"; do [ "$i" -gt 0 ] && out+="$SEP"; out+="${parts[$i]}"; done
printf '%s' "$out"
EOF

# Reinstalling is the update path, so only touch what actually changed.
if [ -f "$SCRIPT" ] && cmp -s "$SCRIPT_TMP" "$SCRIPT"; then
  rm -f "$SCRIPT_TMP"
  SCRIPT_STATE="unchanged"
else
  if [ -f "$SCRIPT" ]; then SCRIPT_STATE="updated"; else SCRIPT_STATE="installed"; fi
  mv "$SCRIPT_TMP" "$SCRIPT"
  chmod 755 "$SCRIPT"
fi

# Update settings.json, keeping whatever is already there
WANT='{"type":"command","command":"bash ~/.claude/statusline-command.sh"}'
if [ -f "$SETTINGS" ]; then
  if "$JQ" -e --argjson want "$WANT" '.statusLine == $want' "$SETTINGS" >/dev/null 2>&1; then
    echo "✓ settings.json already points at the status line; left untouched"
  else
    BACKUP="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    tmp=$(mktemp)
    if "$JQ" --argjson want "$WANT" '. + {"statusLine": $want}' "$SETTINGS" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$SETTINGS"
      echo "✓ settings.json updated (backup: $BACKUP)"
    else
      rm -f "$tmp"
      echo "✗ could not update $SETTINGS; it was left untouched (backup: $BACKUP)" >&2
      exit 1
    fi
  fi
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

case "$SCRIPT_STATE" in
  installed) echo "✓ Status line installed. Restart Claude Code to activate." ;;
  updated)   echo "✓ Status line updated. Restart Claude Code to pick it up." ;;
  unchanged) echo "✓ Status line already up to date." ;;
esac
echo ""
echo "Optional: install claude-credits for detailed weekly usage check:"
if [ -f "$(dirname "$0")/claude-credits" ]; then
  echo "  sudo install -m 755 '$(dirname "$0")/claude-credits' /usr/local/bin/claude-credits"
else
  echo "  sudo curl -fsSL $RAW_BASE/claude-credits -o /usr/local/bin/claude-credits"
  echo "  sudo chmod +x /usr/local/bin/claude-credits"
fi
