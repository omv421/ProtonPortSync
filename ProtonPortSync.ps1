#Requires -Version 5.1
<#
================================================================================
  ProtonVPN  ->  qBittorrent   forwarded-port sync            (fast version)
================================================================================

  WHAT IT DOES
    1. Makes sure ProtonVPN is running.
    2. Reads the currently forwarded port out of the ProtonVPN log.
    3. Puts that port into qBittorrent.

  TWO THINGS ABOUT PROTONVPN THAT SHAPE THIS SCRIPT
    1. Proton VPN 4.4.1 has NO auto-connect. Checked 2026-07-24 by searching the
       app's own files - the feature simply is not there. The app does start
       itself with Windows, but it starts DISCONNECTED. So "open but not
       connected" is not a rare edge case, it is the normal state every time the
       PC boots, and it is the case this script has to handle best.
    2. When you disconnect, the ProtonVPN network adapter does not switch to
       "Down" - it DISAPPEARS from Windows completely. A check written only for
       "Down" would decide you were still connected. That is why the check below
       also reads the log for "Status updated to Disconnected".

  WHAT IT COPES WITH
    ProtonVPN closed .............. starts it, waits for it to connect
    ProtonVPN open, NOT connected . opens its window so you can press Connect,
                                    then carries on by itself once you do
    qBittorrent closed ............ starts it with the right port already set
    qBittorrent already running ... changes the port live, WITHOUT restarting it
    Port already correct .......... notices, and does nothing

  HOW TO RUN IT
      Double-click ProtonPortSync.exe
      or: powershell -ExecutionPolicy Bypass -File "where/you/saved/it/at/ProtonPortSync.ps1"

  OPTIONS
      -Watch          stay running and re-sync whenever ProtonVPN changes the
                      port. Press Ctrl+C to stop.
      -Force          apply the port even if it already looks correct.
      -NoRestart      never kill qBittorrent; only use the Web UI.
      -NoWebUiSetup   do not touch the Web UI settings in qBittorrent.ini.
      -DryRun         find the port and SHOW what it would change, but change
                      nothing. Nothing gets started, stopped, or written.
      -PortOnly       start the VPN and find the port, then stop. qBittorrent
                      is not touched at all. Handy for testing.
      -NoHold         do not pause at the end when double-clicked.
      -VpnLogPath     read a different log file. Only used for testing.
      -TimeoutSeconds how long to wait for a port. Default 90.

  ABOUT THE WEB UI
    Changing the port without restarting qBittorrent needs its Web UI switched
    on. The first run sets that up, for this PC only:
        WebUI\Enabled         = true
        WebUI\Address         = 127.0.0.1   (this PC only - NOT open to the VPN)
        WebUI\LocalHostAuth   = false       (no login needed from this PC)
        WebUI\Password_PBKDF2 = <random>    (see below)

    The password is not optional. qBittorrent 5.x refuses to open the Web UI at
    all when no password has ever been set - even with the localhost login
    bypassed. Measured 2026-07-24: Enabled=true on its own left port 8080 shut,
    with nothing in any log saying why, and this script quietly fell back to
    restarting qBittorrent every single time. A random password is only ADDED
    when none exists. One you set yourself is never touched or read.

    The address matters too. The old value was "*", which listens on every
    network card including the VPN itself. 127.0.0.1 cannot be reached from
    anywhere but this PC.

    To undo: qBittorrent -> Tools -> Options -> Web UI -> untick it.
    Or run with -NoWebUiSetup and it will leave all of those alone.
================================================================================
#>

[CmdletBinding()]
param(
    [switch] $Watch,
    [switch] $Force,
    [switch] $NoRestart,
    [switch] $NoWebUiSetup,
    [switch] $DryRun,
    [switch] $PortOnly,
    [switch] $NoHold,
    [string] $VpnLogPath,
    [int]    $TimeoutSeconds = 90
)

$ErrorActionPreference = 'Continue'
$ProgressPreference     = 'SilentlyContinue'   # Invoke-* is far faster without the progress bar

# ------------------------------------------------------------------ config --
$Cfg = @{
    ProtonExe  = 'C:\Program Files\Proton\VPN\ProtonVPN.Launcher.exe'
    ProtonLog  = Join-Path $env:LOCALAPPDATA 'Proton\Proton VPN\Logs\client-logs.txt'
    QbExe      = 'C:\Program Files\qBittorrent\qbittorrent.exe'
    QbIni      = Join-Path $env:APPDATA 'qBittorrent\qBittorrent.ini'
    WebUiHost  = '127.0.0.1'
    WebUiPort  = 8080
    ScriptLog  = Join-Path $env:TEMP 'vpn_qbittorrent_log.txt'
    PollMs     = 300
    TailBytes  = 262144        # 256 KB of log is plenty; the file rotates well below this
    WatchMs    = 5000
}
$WebUiUrl = 'http://{0}:{1}' -f $Cfg.WebUiHost, $Cfg.WebUiPort

# Lets a test point this at a stand-in log, so the watching can be proven without
# making the real VPN drop and reconnect.
if ($VpnLogPath) { $Cfg.ProtonLog = $VpnLogPath }

# ---------------------------------------------------------------- logging ---
$script:T0 = Get-Date

function Write-Log {
    param([string]$Message, [System.ConsoleColor]$Color = 'Gray')
    $elapsed = ((Get-Date) - $script:T0).TotalSeconds
    $line = '{0:HH:mm:ss}  {1,6:0.0}s  {2}' -f (Get-Date), $elapsed, $Message
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -LiteralPath $Cfg.ScriptLog -Value $line -Encoding UTF8 } catch { }
}

function Write-Fail {
    param([string]$Message)
    Write-Log "ERROR: $Message" 'Red'
}

function Test-StartedByDoubleClick {
    # True when Windows Explorer launched us, i.e. the icon was double-clicked.
    # A normal run finishes in a fraction of a second, so without this the window
    # would flash and vanish before anything could be read.
    try {
        $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
        return ((Get-Process -Id $parentId -ErrorAction Stop).ProcessName -eq 'explorer')
    } catch {
        return $false
    }
}

function Stop-Script {
    param([int]$Code = 0)
    if (-not $NoHold -and (Test-StartedByDoubleClick)) {
        Write-Host ''
        if ($Code -eq 0) {
            Write-Host 'Closing in 6 seconds...' -ForegroundColor DarkGray
            Start-Sleep -Seconds 6
        } else {
            Write-Host 'Something went wrong. Press any key to close.' -ForegroundColor Red
            try   { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
            catch { Start-Sleep -Seconds 30 }
        }
    }
    exit $Code
}

# ------------------------------------------------- ProtonVPN log -> a port --

# ProtonVPN writes two useful lines. Example of each, straight from your log:
#   2026-07-25T01:25:19.351Z | INFO | APP | Port forwarding port changed from '' to '63368'.
#   2026-07-25T01:25:29.141Z | INFO | PROCESS.COMM | Received PortForwarding Status
#       'SleepingUntilRefresh' triggered at '...', Port pair 63368->63368, expiring in 00:01:00 ...
# The first fires once. The second repeats roughly every minute, so it tells us
# the live port even when nothing has changed. We read both and take the newest.
# Note the "\r?$" endings. The log uses Windows line endings, and in .NET a
# multiline "$" only matches just before the \n - never before the \r. Without
# the "\r?" these patterns match nothing at all on a real log file.
$script:RxChanged = [regex]"(?m)^(?<line>[^\r\n]*Port forwarding port changed from '[^']*' to '(?<port>\d*)'[^\r\n]*)\r?$"
$script:RxStatus  = [regex]"(?m)^(?<line>[^\r\n]*Received PortForwarding Status '(?<status>[^']*)'[^\r\n]*?Port pair (?<port>\d+)->\d+[^\r\n]*)\r?$"
$script:RxStamp   = [regex]"^\s*(?<ts>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)"
# Statuses that mean the mapping is gone or breaking - never trust a port from these.
$script:RxDeadStatus = [regex]'(?i)error|fail|stopp|disconnect|expired'

function Read-LogTail {
    param([string]$Path, [int]$Bytes)
    $fs = $null
    try {
        # FileShare.ReadWrite so ProtonVPN can keep writing while we read.
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
                                     [System.IO.FileAccess]::Read,
                                     [System.IO.FileShare]::ReadWrite)
        if ($fs.Length -gt $Bytes) { [void]$fs.Seek(-$Bytes, [System.IO.SeekOrigin]::End) }
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $sr.Dispose()          # also closes $fs
        $fs = $null
        return $text
    } catch {
        return $null
    } finally {
        if ($fs) { try { $fs.Dispose() } catch { } }
    }
}

function ConvertTo-LocalStamp {
    param([string]$Line)
    $m = $script:RxStamp.Match($Line)
    if (-not $m.Success) { return $null }
    $text = $m.Groups['ts'].Value -replace ',', '.'
    # Proton stamps end in Z (UTC). DateTimeOffset handles the conversion to local.
    $dto = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($text, [ref]$dto)) { return $dto.LocalDateTime }
    $dt = [datetime]::MinValue
    if ([datetime]::TryParse($text, [ref]$dt)) { return $dt }
    return $null
}

function Test-VpnConnected {
    <# Is the VPN actually CONNECTED, not merely open?
       This matters more than it looks. ProtonVPN can sit open and disconnected
       all day, and the log still holds the port from the last time it WAS
       connected. Without this check the script happily reads that dead port and
       feeds it to qBittorrent, which then listens on a port nobody forwards. #>

    # The tunnel adapter is the honest answer: Windows only marks it Up while the
    # tunnel is really carrying traffic.
    try {
        $proton = @(Get-NetAdapter -ErrorAction Stop |
                    Where-Object { $_.Name -like '*Proton*' -or $_.InterfaceDescription -like '*Proton*' })
        if ($proton.Count -gt 0) {
            return (@($proton | Where-Object { $_.Status -eq 'Up' }).Count -gt 0)
        }
    } catch { }

    # No Proton adapter at all on this PC. Fall back to what the log last said.
    $text = Read-LogTail -Path $Cfg.ProtonLog -Bytes $Cfg.TailBytes
    if (-not $text) { return $false }
    $states = [regex]::Matches($text, 'Status updated to (?<s>\w+)')
    if ($states.Count -eq 0) { return $false }
    return ($states[$states.Count - 1].Groups['s'].Value -eq 'Connected')
}

function Get-NewestPortEvent {
    <# Returns @{ Port = <int, 0 means "no port right now">; Time = <datetime> } or $null. #>
    $text = Read-LogTail -Path $Cfg.ProtonLog -Bytes $Cfg.TailBytes
    if (-not $text) { return $null }

    $best = $null
    foreach ($rx in @($script:RxChanged, $script:RxStatus)) {
        foreach ($m in $rx.Matches($text)) {
            $line = $m.Groups['line'].Value

            $port = 0
            if ($m.Groups['port'].Value -ne '') { $port = [int]$m.Groups['port'].Value }

            # A status line during an error/teardown is not evidence of a live port.
            if ($m.Groups['status'].Success -and $script:RxDeadStatus.IsMatch($m.Groups['status'].Value)) {
                $port = 0
            }

            $when = ConvertTo-LocalStamp $line
            if (-not $when) { continue }

            if ((-not $best) -or ($when -gt $best.Time)) {
                $best = @{ Port = $port; Time = $when }
            }
        }
    }
    return $best
}

function Wait-ForVpnPort {
    # $FreshAfter is deliberately untyped: it is a [datetime] when we launched the
    # VPN ourselves and $null when it was already running. PowerShell 5.1 refuses
    # to bind $null to a [datetime] parameter.
    param([int]$TimeoutSeconds, $FreshAfter)

    if (-not (Test-Path -LiteralPath $Cfg.ProtonLog)) {
        Write-Fail "ProtonVPN log not found: $($Cfg.ProtonLog)"
        return 0
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastMsg  = ''
    $stale    = $null

    while ((Get-Date) -lt $deadline) {

        # Nothing in the log can be trusted until the tunnel is actually up. An
        # open-but-disconnected ProtonVPN still has the last session's port
        # sitting in the log, and that port is dead.
        if (-not (Test-VpnConnected)) {
            $msg = 'ProtonVPN is open but NOT connected. Waiting for you to connect it...'
            if ($msg -ne $lastMsg) { Write-Log $msg 'Yellow'; $lastMsg = $msg }
            Start-Sleep -Milliseconds $Cfg.PollMs
            continue
        }

        $evt = Get-NewestPortEvent

        if ($evt -and $evt.Port -gt 0) {
            if (-not $FreshAfter) { return $evt.Port }              # VPN was already up: newest is current
            # We just launched the VPN, so ignore a port left over from before.
            # 2 minutes of slack absorbs any clock skew between the log and us.
            if ($evt.Time -gt $FreshAfter.AddMinutes(-2)) { return $evt.Port }
            $stale = $evt.Port
        }

        $msg = 'Waiting for ProtonVPN to forward a port...'
        if ($evt -and $evt.Port -eq 0) { $msg = 'VPN connected, port not assigned yet...' }
        if ($msg -ne $lastMsg) { Write-Log $msg 'DarkYellow'; $lastMsg = $msg }

        Start-Sleep -Milliseconds $Cfg.PollMs
    }

    if ($stale) {
        Write-Log "Timed out waiting for a fresh port; using the newest one found ($stale)." 'Yellow'
        return $stale
    }

    # Say which of the two things actually went wrong. Blaming port forwarding
    # when the VPN simply never connected sends you looking in the wrong place.
    if (-not (Test-VpnConnected)) {
        Write-Fail "ProtonVPN never connected, after waiting $TimeoutSeconds seconds. Press Connect in ProtonVPN, then run this again."
    } else {
        Write-Fail "ProtonVPN is connected but handed out no port in $TimeoutSeconds seconds. Check that port forwarding is switched on in ProtonVPN's settings."
    }
    return 0
}

# ------------------------------------------------------- qBittorrent: ini ---

function Get-IniLines {
    param([string]$Path)
    return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
}

function Set-IniValue {
    <# Sets Key=Value inside [Section]. Adds the key, or the whole section, if missing.
       Returns the modified line array, or $null when nothing needed changing. #>
    param([string[]]$Lines, [string]$Section, [string]$Key, [string]$Value)

    $target  = '{0}={1}' -f $Key, $Value
    $keyRx   = '^\s*' + [regex]::Escape($Key) + '\s*='
    $inside  = $false
    $out     = New-Object System.Collections.Generic.List[string]
    $done    = $false
    $changed = $false
    $sectionSeen = $false
    $sectionEndIndex = -1

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match '^\s*\[') {
            if ($inside) { $inside = $false; if ($sectionEndIndex -lt 0) { $sectionEndIndex = $out.Count } }
            if ($line -match ('^\s*\[' + [regex]::Escape($Section) + '\]\s*$')) { $inside = $true; $sectionSeen = $true }
        }
        elseif ($inside -and -not $done -and $line -match $keyRx) {
            if ($line -ne $target) { $changed = $true }
            $line = $target
            $done = $true
        }

        $out.Add($line)
    }

    if ($inside -and $sectionEndIndex -lt 0) { $sectionEndIndex = $out.Count }

    if (-not $done) {
        if ($sectionSeen) {
            $out.Insert($sectionEndIndex, $target)      # key missing: add it to its section
        } else {
            $out.Add('')                                # section missing: create it
            $out.Add("[$Section]")
            $out.Add($target)
        }
        $changed = $true
    }

    if (-not $changed) { return $null }
    return $out.ToArray()
}

function Save-Ini {
    param([string]$Path, [string[]]$Lines)
    Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force -ErrorAction SilentlyContinue
    # UTF-8 with NO byte-order-mark. Set-Content would have used the old Windows
    # codepage and mangled any accented characters in your save paths.
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Test-IniKeyHasValue {
    <# True when the key exists in that section AND is not blank. #>
    param([string[]]$Lines, [string]$Section, [string]$Key)
    $keyRx  = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+)$'
    $inside = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[') {
            $inside = ($line -match ('^\s*\[' + [regex]::Escape($Section) + '\]\s*$'))
        }
        elseif ($inside -and $line -match $keyRx) {
            return ($Matches[1].Trim() -ne '' -and $Matches[1].Trim() -ne '""')
        }
    }
    return $false
}

function New-QbPasswordHash {
    <# qBittorrent 5.x will NOT start its Web UI unless a password hash exists,
       even with the localhost login bypassed. Proven here on 2026-07-24: with
       WebUI\Enabled=true but no WebUI\Password_PBKDF2, port 8080 never opened.
       Format is @ByteArray(<base64 salt>:<base64 key>), PBKDF2-HMAC-SHA512,
       100000 iterations, 16-byte salt, 64-byte key.
       The argument is named $Secret, not $Password, on purpose: PowerShell's
       linter flags any [string]$Password. A SecureString would be ceremony here
       anyway - this value is generated randomly a line earlier, hashed, and
       dropped. It is never stored or sent anywhere. #>
    param([string]$Secret)
    $salt = New-Object byte[] 16
    $rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($salt)
    $kdf  = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
                $Secret, $salt, 100000, [System.Security.Cryptography.HashAlgorithmName]::SHA512)
    return ('@ByteArray({0}:{1})' -f [Convert]::ToBase64String($salt),
                                     [Convert]::ToBase64String($kdf.GetBytes(64)))
}

function New-RandomPassword {
    $bytes = New-Object byte[] 18
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    return ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '')
}

function Get-IniPort {
    param([string]$Path)
    try {
        foreach ($line in (Get-IniLines $Path)) {
            if ($line -match '^\s*Session\\Port\s*=\s*(\d+)') { return [int]$Matches[1] }
        }
    } catch { }
    return 0
}

# ---------------------------------------------------- qBittorrent: Web UI ---

function Connect-WebUi {
    param([string]$Url)
    try {
        $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $null = Invoke-RestMethod -Uri "$Url/api/v2/app/version" -WebSession $s `
                                  -Headers @{ Referer = $Url } -TimeoutSec 4 -UseBasicParsing
        return $s
    } catch {
        return $null
    }
}

function Get-WebUiPort {
    param($Session, [string]$Url)
    try {
        $prefs = Invoke-RestMethod -Uri "$Url/api/v2/app/preferences" -WebSession $Session `
                                   -Headers @{ Referer = $Url } -TimeoutSec 5 -UseBasicParsing
        return [int]$prefs.listen_port
    } catch { return 0 }
}

function Set-WebUiPort {
    param($Session, [string]$Url, [int]$Port)
    try {
        $body = @{ json = ('{{"listen_port":{0}}}' -f $Port) }
        $null = Invoke-RestMethod -Uri "$Url/api/v2/app/setPreferences" -Method Post `
                                  -Body $body -WebSession $Session `
                                  -Headers @{ Referer = $Url } -TimeoutSec 10 -UseBasicParsing
        return $true
    } catch {
        Write-Log "Web UI refused the change: $($_.Exception.Message)" 'Yellow'
        return $false
    }
}

# ------------------------------------------------ qBittorrent: process ------

function Stop-QBittorrent {
    $procs = @(Get-Process -Name 'qbittorrent' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return }

    Write-Log 'Closing qBittorrent...' 'DarkYellow'
    foreach ($p in $procs) { try { [void]$p.CloseMainWindow() } catch { } }

    # Short grace period on purpose. qBittorrent is normally set to minimise to
    # the tray when closed, so the polite request is simply ignored and the wait
    # always runs to the end. Measured at 8 seconds wasted on every fallback run.
    # We still ASK first, because a clean exit saves resume data properly - but
    # we stop waiting quickly. The old script never asked at all, it went
    # straight to a force kill, so this is still the gentler of the two.
    $deadline = (Get-Date).AddSeconds(2.5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Name 'qbittorrent' -ErrorAction SilentlyContinue)) {
            Write-Log 'qBittorrent closed cleanly.' 'DarkGray'
            return
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Log 'qBittorrent ignored the close request; forcing it.' 'Yellow'
    Stop-Process -Name 'qbittorrent' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Wait-PortListening {
    param([int]$Port, [int]$TimeoutSeconds = 40)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 400
    }
    return $false
}

# ------------------------------------------------------------ the sync -----

function Sync-Port {
    param([int]$Port)

    $running = @(Get-Process -Name 'qbittorrent' -ErrorAction SilentlyContinue).Count -gt 0

    # ---- fast path: qBittorrent is up and its Web UI answers -> change it live
    if ($running) {
        $session = Connect-WebUi $WebUiUrl
        if ($session) {
            $current = Get-WebUiPort $session $WebUiUrl
            if ($current -eq $Port -and -not $Force) {
                Write-Log "Already on port $Port. Nothing to do." 'Green'
                return $true
            }
            if ($DryRun) {
                Write-Log "DRY RUN: would set the port live to $Port via the Web UI (was $current). Nothing changed." 'Cyan'
                return $true
            }
            if (Set-WebUiPort $session $WebUiUrl $Port) {
                Write-Log "Port set to $Port live - no restart needed." 'Green'
                return $true
            }
        } else {
            Write-Log 'Web UI not answering; falling back to restarting qBittorrent.' 'Yellow'
        }
    }

    if ($running -and $NoRestart) {
        Write-Fail 'Could not use the Web UI and -NoRestart was given. Stopping.'
        return $false
    }

    # ---- slow path: edit the settings file, then start qBittorrent
    if (-not (Test-Path -LiteralPath $Cfg.QbIni)) {
        Write-Fail "qBittorrent.ini not found: $($Cfg.QbIni)"
        return $false
    }

    if ((Get-IniPort $Cfg.QbIni) -eq $Port -and -not $running -and -not $Force) {
        Write-Log "Settings file already has port $Port; just starting qBittorrent." 'Green'
    }

    if (-not $DryRun) { Stop-QBittorrent }

    $lines   = Get-IniLines $Cfg.QbIni
    $touched = $false

    $updated = Set-IniValue -Lines $lines -Section 'BitTorrent' -Key 'Session\Port' -Value "$Port"
    if ($updated) { $lines = $updated; $touched = $true; Write-Log "Settings file: Session\Port = $Port" 'DarkGray' }

    # Switch the Web UI on so every future run can take the instant path.
    # Localhost only, no password from this PC. See the note at the top.
    if (-not $NoWebUiSetup) {
        $webUiChanges = @(
            @{ Key = 'WebUI\Enabled';       Value = 'true' },
            @{ Key = 'WebUI\Address';       Value = $Cfg.WebUiHost },
            @{ Key = 'WebUI\Port';          Value = "$($Cfg.WebUiPort)" },
            @{ Key = 'WebUI\LocalHostAuth'; Value = 'false' }
        )
        $anyWebUi = $false
        foreach ($c in $webUiChanges) {
            $updated = Set-IniValue -Lines $lines -Section 'Preferences' -Key $c.Key -Value $c.Value
            if ($updated) { $lines = $updated; $touched = $true; $anyWebUi = $true }
        }

        # qBittorrent 5.x will not open the Web UI at all when no password hash
        # exists - not even with the localhost login bypassed. Measured here on
        # 2026-07-24: Enabled=true alone left port 8080 shut. Only ever ADD one;
        # never overwrite a password the user has set themselves.
        if (-not (Test-IniKeyHasValue -Lines $lines -Section 'Preferences' -Key 'WebUI\Password_PBKDF2')) {
            $hash    = New-QbPasswordHash (New-RandomPassword)
            $updated = Set-IniValue -Lines $lines -Section 'Preferences' `
                                    -Key 'WebUI\Password_PBKDF2' -Value ('"' + $hash + '"')
            if ($updated) { $lines = $updated; $touched = $true; $anyWebUi = $true }
            Write-Log 'Web UI had no password set, which stops qBittorrent opening it at all. Added a random one.' 'DarkGray'
        }

        if ($anyWebUi) {
            Write-Log "Web UI switched on at $WebUiUrl - this PC only, no login needed. Future runs will not restart qBittorrent." 'Cyan'
        }
    }

    if (-not (Test-Path -LiteralPath $Cfg.QbExe)) {
        Write-Fail "qBittorrent not found: $($Cfg.QbExe)"
        return $false
    }

    if ($DryRun) {
        if ($touched) {
            Write-Log 'DRY RUN: the settings file WOULD change to this. Nothing was written:' 'Cyan'
            foreach ($l in $lines) {
                if ($l -match '^\s*(Session\\Port|WebUI\\(Enabled|Address|Port|LocalHostAuth))\s*=') {
                    Write-Log "           $l" 'Cyan'
                }
            }
        } else {
            Write-Log 'DRY RUN: the settings file already says the right thing; no change needed.' 'Cyan'
        }
        Write-Log 'DRY RUN: would then restart qBittorrent. Nothing was started or stopped.' 'Cyan'
        return $true
    }

    if ($touched) {
        Save-Ini -Path $Cfg.QbIni -Lines $lines
        Write-Log "Saved qBittorrent.ini (backup: qBittorrent.ini.bak)." 'DarkGray'
    }

    Write-Log 'Starting qBittorrent...' 'DarkYellow'
    Start-Process -FilePath $Cfg.QbExe | Out-Null

    if (Wait-PortListening -Port $Port -TimeoutSeconds 40) {
        Write-Log "qBittorrent is up and listening on $Port." 'Green'
        return $true
    }
    Write-Log "qBittorrent started, but port $Port is not listening yet. Check it in the app." 'Yellow'
    return $true
}

# ---------------------------------------------------------------- main -----

Write-Log '--- ProtonVPN -> qBittorrent port sync ---' 'White'

# 1. ProtonVPN up?
$freshAfter = $null
if (-not (Get-Process -Name 'ProtonVPN*' -ErrorAction SilentlyContinue)) {
    if (-not (Test-Path -LiteralPath $Cfg.ProtonExe)) {
        Write-Fail "ProtonVPN not found: $($Cfg.ProtonExe)"
        Stop-Script 1
    }
    if ($DryRun) {
        Write-Log 'DRY RUN: ProtonVPN is not running. Would start it. Nothing started.' 'Cyan'
    } else {
        Write-Log 'Starting ProtonVPN...' 'DarkYellow'
        Start-Process -FilePath $Cfg.ProtonExe | Out-Null
        # Ignore any port left over from the last session. Note the wait from here
        # on is ProtonVPN connecting - this script cannot make that part quicker.
        $freshAfter = $script:T0
    }
} else {
    Write-Log 'ProtonVPN already running.' 'DarkGray'

    # Open but not connected. Bring its window up so it can be connected with one
    # click, and treat everything already in the log as belonging to an older
    # session, because it does.
    if (-not (Test-VpnConnected)) {
        Write-Log 'ProtonVPN is open but not connected.' 'Yellow'
        if (-not $DryRun) {
            Write-Log 'Opening the ProtonVPN window - press Connect and this will carry on by itself.' 'Yellow'
            try { Start-Process -FilePath $Cfg.ProtonExe | Out-Null } catch { }
            $freshAfter = Get-Date
        }
    }
}

# 2. Which port?
$tPort = Get-Date
$port  = Wait-ForVpnPort -TimeoutSeconds $TimeoutSeconds -FreshAfter $freshAfter
if ($port -le 0) { Stop-Script 1 }
Write-Log ('Forwarded port: {0}   (found in {1:0.0}s)' -f $port, ((Get-Date) - $tPort).TotalSeconds) 'Green'

if ($PortOnly) {
    Write-Log 'PortOnly: stopping here. qBittorrent was not touched.' 'Cyan'
    Stop-Script 0
}

# 3. Put it into qBittorrent.
if (-not (Sync-Port -Port $port)) { Stop-Script 1 }

Write-Log ('Done in {0:0.0} seconds.' -f ((Get-Date) - $script:T0).TotalSeconds) 'White'

# 4. Optional: stay running and follow the port.
if ($Watch) {
    Write-Log 'Watching for port changes. Press Ctrl+C to stop.' 'Cyan'
    $applied = $port
    while ($true) {
        Start-Sleep -Milliseconds $Cfg.WatchMs
        $evt = Get-NewestPortEvent
        if ($evt -and $evt.Port -gt 0 -and $evt.Port -ne $applied) {
            Write-Log "ProtonVPN changed the port: $applied -> $($evt.Port)" 'Cyan'
            $script:T0 = Get-Date
            if (Sync-Port -Port $evt.Port) { $applied = $evt.Port }
        }
    }
}

Stop-Script 0
