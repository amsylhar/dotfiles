# Claude Code Status Line Installer for Windows
# Ejecutar con: irm https://raw.githubusercontent.com/amsylhar/dotfiles/master/install-statusline.ps1 | iex

$ClaudeDir = "$env:USERPROFILE\.claude"
$Script    = "$ClaudeDir\statusline-command.ps1"
$Settings  = "$ClaudeDir\settings.json"

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)

# Escribir el script de status line
$scriptContent = @'
$input_data = $input | Out-String | ConvertFrom-Json

$ESC   = [char]27
$RED   = "$ESC[31m"
$YELLOW= "$ESC[33m"
$GREEN = "$ESC[32m"
$BLUE  = "$ESC[34m"
$CYAN  = "$ESC[36m"
$DIM   = "$ESC[2m"
$BOLD  = "$ESC[1m"
$RESET = "$ESC[0m"
$SEP   = "$DIM │ $RESET"

function Get-Color($pct) {
    if ($pct -ge 80) { return $RED }
    elseif ($pct -ge 50) { return $YELLOW }
    else { return $GREEN }
}

function Get-Bar($pct) {
    $filled = [math]::Floor($pct * 8 / 100)
    $empty  = 8 - $filled
    return ("█" * $filled) + ("░" * $empty)
}

$model     = $input_data.model.display_name
$used      = $input_data.context_window.used_percentage
$five_hr   = $input_data.rate_limits.five_hour.used_percentage
$seven_day = $input_data.rate_limits.seven_day.used_percentage
$vim_mode  = $input_data.vim.mode
$agent     = $input_data.agent.name

$parts = @()

if ($vim_mode)  { $parts += "${YELLOW}${vim_mode}${RESET}" }
if ($agent)     { $parts += "${CYAN}⚙ ${agent}${RESET}" }

$parts += "${BOLD}${BLUE}${model}${RESET}"

if ($null -ne $used) {
    $pct = [math]::Round($used)
    $col = Get-Color $pct
    $bar = Get-Bar $pct
    $parts += "${col}${bar} ${pct}%${RESET}"
}
if ($null -ne $five_hr) {
    $pct = [math]::Round($five_hr)
    $col = Get-Color $pct
    $bar = Get-Bar $pct
    $parts += "${DIM}5h${RESET} ${col}${bar} ${pct}%${RESET}"
}
if ($null -ne $seven_day) {
    $pct = [math]::Round($seven_day)
    $col = Get-Color $pct
    $bar = Get-Bar $pct
    $parts += "${DIM}7d${RESET} ${col}${bar} ${pct}%${RESET}"
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host ($parts -join $SEP) -NoNewline
'@
[System.IO.File]::WriteAllText($Script, $scriptContent, $utf8NoBOM)

# Actualizar settings.json
$statusLineConfig = @{
    statusLine = @{
        type    = "command"
        command = "powershell -NoProfile -File ~/.claude/statusline-command.ps1"
    }
}

if (Test-Path $Settings) {
    $existing = Get-Content $Settings -Raw | ConvertFrom-Json
    $existing | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineConfig.statusLine -Force
    [System.IO.File]::WriteAllText($Settings, ($existing | ConvertTo-Json -Depth 5), $utf8NoBOM)
} else {
    [System.IO.File]::WriteAllText($Settings, ($statusLineConfig | ConvertTo-Json -Depth 5), $utf8NoBOM)
}

Write-Host "Instalado. Reinicia Claude Code para ver la status line."
