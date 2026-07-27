#Requires -Version 5.1
<#
================================================================================
  Make ProtonPortSync run itself when you log in
================================================================================

  Turn it on:
      powershell -ExecutionPolicy Bypass -File Install-AtLogin.ps1

  Turn it off:
      powershell -ExecutionPolicy Bypass -File Install-AtLogin.ps1 -Remove

  WHAT IT ACTUALLY DOES AT LOGIN

  Not what you might expect, and the difference matters.

  Proton VPN launches itself when Windows starts, but it launches DISCONNECTED,
  unless you have switched on Settings, General, Auto-startup, Auto-connect,
  which is off by default and easy to miss. So at
  the moment you log in there is no tunnel and no forwarded port, and there will
  not be one until you press Connect.

  A plain "run this at login" shortcut would therefore fire into an empty room,
  find nothing, and give up.

  Instead this starts hidden and WAITS, up to 30 minutes, for you to connect.
  The moment you do, it syncs the port and exits. If you never connect, it
  leaves quietly having done nothing.

  So the routine becomes: turn the PC on, press Connect in Proton whenever you
  feel like it, and the port is handled. You never touch the tool.

  It runs hidden, so there is no console window. To see what it did, open:
      %TEMP%\vpn_qbittorrent_log.txt

  Only one copy runs at a time. Logging out and back in without rebooting will
  not stack up a second one.
================================================================================
#>

[CmdletBinding()]
param([switch]$Remove)

$ErrorActionPreference = 'Stop'

$root      = $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
$startup   = [Environment]::GetFolderPath('Startup')
$vbsName   = 'ProtonPortSync.vbs'
$vbsTarget = Join-Path $startup $vbsName

function Write-Step { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Info { param([string]$m) Write-Host "   $m" -ForegroundColor DarkGray }

# ------------------------------------------------------------------ remove --
if ($Remove) {
    Write-Step "`nTurning off the login start"
    if (Test-Path -LiteralPath $vbsTarget) {
        Remove-Item -LiteralPath $vbsTarget -Force
        Write-Info "deleted $vbsTarget"
        Write-Host "`nDone. It will not start on its own any more. The exe still works when you double-click it.`n" -ForegroundColor Green
    } else {
        Write-Info 'nothing was installed, so nothing to remove'
        Write-Host ''
    }
    return
}

# ----------------------------------------------------------------- install --
Write-Step "`n1. finding what to launch"

# Prefer the exe. Fall back to the script if the exe has not been built.
$exe = Join-Path $root 'ProtonPortSync.exe'
$ps1 = Join-Path $root 'ProtonPortSync.ps1'

if (Test-Path -LiteralPath $exe) {
    $target = $exe
    $cmd    = '""' + $exe + '"" -AtLogin'
    Write-Info "using $exe"
} elseif (Test-Path -LiteralPath $ps1) {
    $target = $ps1
    $cmd    = 'powershell -NoProfile -ExecutionPolicy Bypass -File ""' + $ps1 + '"" -AtLogin'
    Write-Info "no exe found, using the script: $ps1"
} else {
    throw "Neither ProtonPortSync.exe nor ProtonPortSync.ps1 is next to this installer ($root)."
}

Write-Step "`n2. writing the hidden launcher"

# A .vbs is used purely to get a hidden window. A .lnk set to "minimised" still
# flashes a console and leaves it on the taskbar; WScript's Run with a window
# style of 0 does not show one at all.
$vbs = @"
' Starts ProtonPortSync at login, with no window.
' Written by Install-AtLogin.ps1. Delete this file to stop it, or run
' Install-AtLogin.ps1 -Remove.
'
' The 0 is the window style, meaning hidden. The False means do not wait for it
' to finish, which matters because it can sit waiting for the VPN for a while.
CreateObject("WScript.Shell").Run "$cmd", 0, False
"@

# ASCII with CRLF. Windows Script Host is old and a BOM upsets it.
[System.IO.File]::WriteAllText($vbsTarget, ($vbs -replace "`r?`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))
Write-Info $vbsTarget

Write-Step "`n3. checking it"
if (-not (Test-Path -LiteralPath $vbsTarget)) { throw 'The launcher was not written.' }
$written = Get-Content -LiteralPath $vbsTarget -Raw
if ($written -notmatch [regex]::Escape($target)) { throw 'The launcher does not point at the right file.' }
Write-Info 'launcher points at the right place'
Write-Info ("target exists: " + (Test-Path -LiteralPath $target))

Write-Host @"

Done. From now on, when you log in:

  - this starts hidden and waits, up to 30 minutes, for the VPN
  - press Connect in Proton whenever you like
  - the port gets synced within a second of you connecting
  - if you never connect, it just leaves

To see what it did:   %TEMP%\vpn_qbittorrent_log.txt
To turn it off:       Install-AtLogin.ps1 -Remove

"@ -ForegroundColor Green
