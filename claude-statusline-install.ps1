# Claude Code Status Line Installer for Windows
# Ejecutar con: irm https://raw.githubusercontent.com/amsylhar/dotfiles/master/claude-statusline-install.ps1 | iex

$ClaudeDir = "$env:USERPROFILE\.claude"
$Script    = "$ClaudeDir\statusline-command.ps1"
$Settings  = "$ClaudeDir\settings.json"

$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)
$utf8BOM   = [System.Text.UTF8Encoding]::new($true)

# Validar settings.json ANTES de escribir nada: ahi viven permissions, hooks,
# mcpServers y todo lo que el usuario configuro. Si no se puede leer, no se toca.
$existing = $null
if (Test-Path $Settings) {
    try {
        $raw = Get-Content $Settings -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $existing = [pscustomobject]@{}
        } else {
            $existing = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    } catch {
        Write-Host "X $Settings existe pero no es JSON valido; no se modifica nada."
        Write-Host "  Arregla o mueve ese archivo y vuelve a ejecutar el instalador."
        return
    }
}

New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# Single-quoted here-string: nothing is expanded, no escaping needed
$scriptContent = @'
# Enable ANSI/VT processing on Windows consoles that need it
if ($Host.UI.SupportsVirtualTerminal -ne $true) {
    try {
        $sig = '[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m); [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);'
        $k = Add-Type -MemberDefinition $sig -Name K32 -Namespace VT -PassThru
        $h = $k::GetStdHandle(-11); $m = 0
        $k::GetConsoleMode($h, [ref]$m) | Out-Null
        $k::SetConsoleMode($h, $m -bor 4) | Out-Null
    } catch {}
}

# Sin JSON utilizable no hay status line que pintar: salir en silencio.
try {
    $input_data = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
} catch {
    return
}
if ($null -eq $input_data) { return }

$INV = [System.Globalization.CultureInfo]::InvariantCulture

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

# Porcentaje -> entero redondeado, sin depender de la cultura del sistema
# (en es-ES "37.6" se parsearia como 376 con TryParse de cultura local).
function Get-Pct($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]) {
        return [int][math]::Round([double]$v, 0, [System.MidpointRounding]::AwayFromZero)
    }
    $d = [double]0
    if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, $INV, [ref]$d)) {
        return [int][math]::Round($d, 0, [System.MidpointRounding]::AwayFromZero)
    }
    return $null
}

# resets_at se espera como epoch unix; se acepta ISO-8601 y se devuelve $null
# ante cualquier otra cosa, para no lanzar excepciones en la aritmetica.
function ConvertTo-Epoch($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [int] -or $v -is [long] -or $v -is [double]) { return [long]$v }
    $n = [long]0
    if ([long]::TryParse([string]$v, [ref]$n)) { return $n }
    try { return [DateTimeOffset]::Parse([string]$v, $INV).ToUnixTimeSeconds() } catch { return $null }
}

# Umbrales, en un solo sitio: color de uso y cuanto puede adelantarse el
# consumo al ciclo antes de que el delta deje de ser verde.
$USAGE_WARN = 50; $USAGE_CRIT = 80
$PACE_OK    = 5;  $PACE_WARN  = 15

function Get-Color($pct) {
    if ($pct -ge $USAGE_CRIT) { return $RED }
    elseif ($pct -ge $USAGE_WARN) { return $YELLOW }
    else { return $GREEN }
}

function Get-Bar($pct) {
    if ($pct -lt 0)   { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $filled = [math]::Floor($pct * 8 / 100)
    $empty  = 8 - $filled
    return ([char]0x2588).ToString() * $filled + ([char]0x2591).ToString() * $empty
}

function Get-DeltaColor($delta) {
    if ($delta -le $PACE_OK) { return $GREEN }
    elseif ($delta -le $PACE_WARN) { return $YELLOW }
    else { return $RED }
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
$used        = Get-Pct $input_data.context_window.used_percentage
$vim_mode    = $input_data.vim.mode
$agent       = $input_data.agent.name
$worktree    = $input_data.worktree.name
$five_hr     = Get-Pct $input_data.rate_limits.five_hour.used_percentage
$five_reset  = ConvertTo-Epoch $input_data.rate_limits.five_hour.resets_at
$seven_day   = Get-Pct $input_data.rate_limits.seven_day.used_percentage
$seven_reset = ConvertTo-Epoch $input_data.rate_limits.seven_day.resets_at

if ($null -ne $seven_day) {
    $resetStr = if ($null -ne $seven_reset) { [string]$seven_reset } else { "" }
    $cacheVal = ([string]::Format($INV, "{0} {1}", $seven_day, $resetStr)).Trim()
    try {
        [System.IO.File]::WriteAllText(
            "$env:USERPROFILE\.claude\credits-cache",
            $cacheVal,
            [System.Text.UTF8Encoding]::new($false)
        )
    } catch {}
}

$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$parts    = @()

if ($vim_mode) { $parts += "${YELLOW}${vim_mode}${RESET}" }
if ($agent)    { $parts += "${CYAN}$([char]0x2699) ${agent}${RESET}" }
if ($worktree) { $parts += "${DIM}$([char]0x2261) ${worktree}${RESET}" }
$parts += "${BOLD}${BLUE}${model}${RESET}"

if ($null -ne $used) {
    $col = Get-Color $used
    $bar = Get-Bar $used
    $parts += "${col}${bar} ${used}%${RESET}"
}

if ($null -ne $five_hr) {
    $col = Get-Color $five_hr
    $bar = Get-Bar $five_hr
    if ($null -ne $five_reset) {
        $diff = $five_reset - $nowEpoch
        if ($diff -gt 0) {
            $remFmt    = Format-Remaining $diff
            $elapsed5h = 5 * 3600 - $diff
            $epct5h    = [math]::Floor($elapsed5h * 100 / (5 * 3600))
            $delta5h   = $five_hr - $epct5h
            $dcol5h    = Get-DeltaColor $delta5h
            $dsign5h   = if ($delta5h -ge 0) { "+" } else { "" }
            $parts    += "${DIM}5h${RESET} ${col}${bar} ${five_hr}%${RESET} ${DIM}${remFmt} (${RESET}${dcol5h}${dsign5h}${delta5h}%${RESET}${DIM})${RESET}"
        } else {
            $parts += "${DIM}5h${RESET} ${col}${bar} ${five_hr}%${RESET} ${DIM}~0m${RESET}"
        }
    } else {
        $parts += "${DIM}5h${RESET} ${col}${bar} ${five_hr}%${RESET}"
    }
}

if ($null -ne $seven_day) {
    $col = Get-Color $seven_day
    $bar = Get-Bar $seven_day
    if ($null -ne $seven_reset) {
        $diff7  = $seven_reset - $nowEpoch
        $totSec = 7 * 86400
        if ($diff7 -gt 0) {
            $elp7   = $totSec - $diff7
            $cicPct = [math]::Floor($elp7 * 100 / $totSec)
            $rem7   = Format-Remaining $diff7
            $delta7 = $seven_day - $cicPct
            $dcol7  = Get-DeltaColor $delta7
            $dsign7 = if ($delta7 -ge 0) { "+" } else { "" }
            $parts += "${DIM}7d${RESET} ${col}${bar} ${seven_day}%${RESET} ${DIM}${rem7} (${RESET}${dcol7}${dsign7}${delta7}%${RESET}${DIM})${RESET}"
        } else {
            $parts += "${DIM}7d${RESET} ${col}${bar} ${seven_day}%${RESET} ${DIM}0h${RESET}"
        }
    } else {
        $parts += "${DIM}7d${RESET} ${col}${bar} ${seven_day}%${RESET}"
    }
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host ($parts -join $SEP) -NoNewline
'@

# Reinstalar es la via de actualizacion, asi que solo se toca lo que cambia.
$scriptState = "installed"
if (Test-Path $Script) {
    $currentScript = ""
    try { $currentScript = [System.IO.File]::ReadAllText($Script) } catch {}
    $scriptState = if ($currentScript -eq $scriptContent) { "unchanged" } else { "updated" }
}
if ($scriptState -ne "unchanged") {
    [System.IO.File]::WriteAllText($Script, $scriptContent, $utf8BOM)
}

$scriptPath = $Script -replace '\\','/'
$wantCommand = "powershell -NoProfile -File '$scriptPath'"
$statusLineConfig = @{
    statusLine = @{
        type    = "command"
        command = $wantCommand
    }
}

if ($null -ne $existing) {
    $sl = $existing.statusLine
    if ($null -ne $sl -and $sl.type -eq "command" -and $sl.command -eq $wantCommand) {
        Write-Host "settings.json ya apunta a la status line; no se modifica"
    } else {
        $backup = "$Settings.bak." + (Get-Date -Format 'yyyyMMddHHmmss')
        Copy-Item $Settings $backup -Force
        $existing | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLineConfig.statusLine -Force
        # -Depth 100: con la profundidad por defecto (2) o con 5, un bloque hooks
        # anidado se serializa como "System.Collections.Hashtable" y se pierde.
        [System.IO.File]::WriteAllText($Settings, ($existing | ConvertTo-Json -Depth 100), $utf8NoBOM)
        Write-Host "settings.json actualizado (backup: $backup)"
    }
} else {
    [System.IO.File]::WriteAllText($Settings, ($statusLineConfig | ConvertTo-Json -Depth 100), $utf8NoBOM)
}

switch ($scriptState) {
    "installed" { Write-Host "Instalado. Reinicia Claude Code para ver la status line." }
    "updated"   { Write-Host "Actualizado. Reinicia Claude Code para cargar la nueva version." }
    "unchanged" { Write-Host "Ya estaba al dia. No hay nada que hacer." }
}
