# Claude Code Status Line Installer for Windows
# Ejecutar con: irm https://raw.githubusercontent.com/amsylhar/dotfiles/master/claude-statusline-install.ps1 | iex

$ClaudeDir = "$env:USERPROFILE\.claude"
$Script    = "$ClaudeDir\statusline-command.ps1"
$Settings  = "$ClaudeDir\settings.json"

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)
$utf8BOM   = [System.Text.UTF8Encoding]::new($true)

# Single-quoted here-string: nothing is expanded, no escaping needed
$scriptContent = @'
$input_data = $input | Out-String | ConvertFrom-Json

$ESC    = [char]27
$RED    = "$ESC[31m"
$YELLOW = "$ESC[33m"
$GREEN  = "$ESC[32m"
$BLUE   = "$ESC[34m"
$CYAN   = "$ESC[36m"
$DIM    = "$ESC[2m"
$BOLD   = "$ESC[1m"
$RESET  = "$ESC[0m"
$SEP    = "$DIM $([char]0x2502) $RESET"

function Get-Color($pct) {
    if ($pct -ge 80) { return $RED }
    elseif ($pct -ge 50) { return $YELLOW }
    else { return $GREEN }
}

function Get-Bar($pct) {
    $filled = [math]::Floor($pct * 8 / 100)
    $empty  = 8 - $filled
    return ([char]0x2588).ToString() * $filled + ([char]0x2591).ToString() * $empty
}

function Format-Remaining($diffSec) {
    $d = [math]::Floor($diffSec / 86400)
    $h = [math]::Floor(($diffSec % 86400) / 3600)
    $m = [math]::Floor(($diffSec % 3600) / 60)
    if ($d -gt 0 -and $h -gt 0) { return "${d}d ${h}h" }
    elseif ($d -gt 0)            { return "${d}d" }
    elseif ($h -gt 0)            { return "${h}h ${m}m" }
    else                         { return "${m}m" }
}

$model       = $input_data.model.display_name
$used        = $input_data.context_window.used_percentage
$vim_mode    = $input_data.vim.mode
$agent       = $input_data.agent.name
$worktree    = $input_data.worktree.name
$five_hr     = $input_data.rate_limits.five_hour.used_percentage
$five_reset  = $input_data.rate_limits.five_hour.resets_at
$seven_day   = $input_data.rate_limits.seven_day.used_percentage
$seven_reset = $input_data.rate_limits.seven_day.resets_at

if ($null -ne $seven_day) {
    $cacheDir  = "$env:USERPROFILE\.claude"
    $resetStr  = if ($null -ne $seven_reset) { $seven_reset } else { "" }
    [System.IO.File]::WriteAllText(
        "$cacheDir\credits-cache",
        "$seven_day $resetStr".Trim(),
        [System.Text.Encoding]::UTF8
    )
}

$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$parts    = @()

if ($vim_mode) { $parts += "${YELLOW}${vim_mode}${RESET}" }
if ($agent)    { $parts += "${CYAN}$([char]0x2699) ${agent}${RESET}" }
if ($worktree) { $parts += "${DIM}$([char]0x2387) ${worktree}${RESET}" }
$parts += "${BOLD}${BLUE}${model}${RESET}"

if ($null -ne $used) {
    $pct  = [math]::Round($used)
    $col  = Get-Color $pct
    $bar  = Get-Bar $pct
    $parts += "${col}${bar} ${pct}%${RESET}"
}

if ($null -ne $five_hr) {
    $fpct = [math]::Round($five_hr)
    $col  = Get-Color $fpct
    $bar  = Get-Bar $fpct
    if ($null -ne $five_reset) {
        $diff = $five_reset - $nowEpoch
        if ($diff -gt 0) {
            $remFmt    = Format-Remaining $diff
            $elapsed5h = 5 * 3600 - $diff
            $epct5h    = [math]::Floor($elapsed5h * 100 / (5 * 3600))
            $delta5h   = $fpct - $epct5h
            $dcol5h    = if ($delta5h -le 5 -and $delta5h -ge -100) { $GREEN } elseif ($delta5h -le 15) { $YELLOW } else { $RED }
            $dsign5h   = if ($delta5h -ge 0) { "+" } else { "" }
            $parts    += "${DIM}5h${RESET} ${col}${bar} ${fpct}%${RESET} ${DIM}${remFmt} (${RESET}${dcol5h}${dsign5h}${delta5h}%${RESET}${DIM})${RESET}"
        } else {
            $parts += "${DIM}5h${RESET} ${col}${bar} ${fpct}%${RESET} ${DIM}~0m${RESET}"
        }
    } else {
        $parts += "${DIM}5h${RESET} ${col}${bar} ${fpct}%${RESET}"
    }
}

if ($null -ne $seven_day) {
    $wpct = [math]::Round($seven_day)
    $col  = Get-Color $wpct
    $bar  = Get-Bar $wpct
    if ($null -ne $seven_reset) {
        $diff7  = $seven_reset - $nowEpoch
        $totSec = 7 * 86400
        if ($diff7 -gt 0) {
            $elp7   = $totSec - $diff7
            $cicPct = [math]::Floor($elp7 * 100 / $totSec)
            $rem7   = Format-Remaining $diff7
            $delta7 = $wpct - $cicPct
            $dcol7  = if ($delta7 -le 5 -and $delta7 -ge -100) { $GREEN } elseif ($delta7 -le 15) { $YELLOW } else { $RED }
            $dsign7 = if ($delta7 -ge 0) { "+" } else { "" }
            $parts += "${DIM}7d${RESET} ${col}${bar} ${wpct}%${RESET} ${DIM}${rem7} (${RESET}${dcol7}${dsign7}${delta7}%${RESET}${DIM})${RESET}"
        } else {
            $parts += "${DIM}7d${RESET} ${col}${bar} ${wpct}%${RESET} ${DIM}0h${RESET}"
        }
    } else {
        $parts += "${DIM}7d${RESET} ${col}${bar} ${wpct}%${RESET}"
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host ($parts -join $SEP) -NoNewline
'@

[System.IO.File]::WriteAllText($Script, $scriptContent, $utf8BOM)

$scriptPath = $Script -replace '\\','/'
$statusLineConfig = @{
    statusLine = @{
        type    = "command"
        command = "powershell -NoProfile -Command `"`$input | & '$scriptPath'`""
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
