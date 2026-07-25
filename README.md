# ProtonPortSync

Keeps qBittorrent's port matched to whatever port Proton VPN is forwarding you. Takes under a second and doesn't restart qBittorrent.

Double click it. That's it.

[![Download](https://img.shields.io/github/v/release/omv421/ProtonPortSync?label=download&color=2ea44f)](https://github.com/omv421/ProtonPortSync/releases/latest/download/ProtonPortSync.exe)
[![Licence](https://img.shields.io/badge/licence-MIT-blue)](LICENSE)

<p align="center">
  <img src="ProtonVPN_qBittorrent_Logo.png" width="180" alt="ProtonPortSync">
</p>

---

## The problem

Proton VPN forwards you a port so people can connect to you. That port changes every time you reconnect.

qBittorrent doesn't know it changed. So it keeps listening on a port that's dead, and your speeds drop off.

Proton VPN on Windows has no command line, so there's nothing official to plug into.

## What it does

1. Checks Proton VPN is running and actually connected.
2. Reads the forwarded port out of Proton VPN's log.
3. Puts that port into qBittorrent while it's still running.

## Why not just restart qBittorrent?

Restarting stops every torrent, then re-checks them, then reconnects. Takes ages.

This talks to qBittorrent's Web API instead. The process is never touched. I checked the process ID before and after, it's the same qBittorrent.

If the Web API isn't reachable it falls back to editing the settings file and restarting. So it always works, it's just slower.

## Speed

These are measured, not guessed.

| Situation | Time |
|---|---|
| VPN connected, port changed | 0.7s, no restart |
| VPN connected, port already right | 0.2s, does nothing |
| qBittorrent closed | 0.9s, starts it with the right port |
| Proton VPN open but not connected | waits for you, then under a second once the tunnel is up |
| Proton VPN closed | about 6s, starts it and waits |

The waiting isn't the tool being slow. That's Proton VPN connecting, and nothing can speed that up.

## What it looks like

Normal run. Proton had reconnected and given me a different port:

```
22:01:55     0.0s  --- ProtonVPN -> qBittorrent port sync ---
22:01:55     0.0s  ProtonVPN already running.
22:01:56     0.7s  Forwarded port: 43130   (found in 0.1s)
22:01:56     0.7s  Port set to 43130 live - no restart needed.
22:01:56     0.7s  Done in 0.7 seconds.
```

Proton VPN open but not connected. It opens the Proton window, waits for you, then finishes on its own:

```
21:44:04     0.0s  --- ProtonVPN -> qBittorrent port sync ---
21:44:04     0.0s  ProtonVPN already running.
21:44:05     0.6s  ProtonVPN is open but not connected.
21:44:05     0.6s  Opening the ProtonVPN window - press Connect and this will carry on by itself.
21:44:05     0.6s  ProtonVPN is open but NOT connected. Waiting for you to connect it...
21:44:11     7.4s  VPN connected, port not assigned yet...
21:44:12     8.1s  Forwarded port: 43130
21:44:12     8.1s  Port set to 43130 live - no restart needed.
21:44:12     8.1s  Done in 8.1 seconds.
```

That `port not assigned yet` line matters. There's a real gap between the tunnel coming up and Proton actually handing out a port. If you grab the first value you see in that gap, you give qBittorrent a dead port from the last session. This waits it out.

Every number here came from a real run. None of them are estimates.

## What it handles

| Situation | What happens |
|---|---|
| Proton VPN closed | Starts it, waits for it to connect |
| Proton VPN open but not connected | Opens its window so you can hit Connect, then carries on by itself |
| qBittorrent closed | Starts it with the right port already set |
| qBittorrent running | Changes the port live, no restart |
| Port already right | Notices, does nothing |
| Proton VPN never connects | Says so and changes nothing |

That second row matters more than it looks. See below for why it's the normal state and not some rare edge case.

## Install

1. [Download ProtonPortSync.exe](https://github.com/omv421/ProtonPortSync/releases/latest/download/ProtonPortSync.exe)
2. Double click it

There's no step 3. No Task Scheduler, no config file to edit, no renaming your network adapter, nothing to turn on by hand.

If you'd rather run the script directly, `ProtonPortSync.ps1` is the same program:

```powershell
powershell -ExecutionPolicy Bypass -File ProtonPortSync.ps1
```

### First run

The first run turns on qBittorrent's Web UI, because that's what lets the port change without a restart. It's set to this PC only:

```
WebUI\Enabled         = true
WebUI\Address         = 127.0.0.1     <- can't be reached from anywhere else
WebUI\LocalHostAuth   = false         <- no login needed from this PC
WebUI\Password_PBKDF2 = <random>
```

Your settings file gets backed up to `qBittorrent.ini.bak` first.

To undo it: qBittorrent, Tools, Options, Web UI, untick. Or run with `-NoWebUiSetup` and it won't touch any of that.

## Options

You don't need any of these. They're here if you want them.

| Option | What it does |
|---|---|
| `-Watch` | Stays running and re-syncs whenever the port changes. Ctrl+C to stop. |
| `-DryRun` | Shows what it would change. Changes nothing, starts nothing. |
| `-Force` | Applies the port even if it already looks right. |
| `-NoRestart` | Never restarts qBittorrent, Web UI only. |
| `-NoWebUiSetup` | Leaves the Web UI settings alone. |
| `-PortOnly` | Just finds and prints the port. Doesn't touch qBittorrent. |
| `-TimeoutSeconds` | How long to wait for a port. Default 90. |

## Two things about Proton VPN that shaped this

Both found by testing. They're why this handles cases other scripts don't.

**1. Proton VPN 4.4.1 has no auto-connect.** It starts with Windows, but it starts disconnected.

So "open but not connected" isn't a rare case. It's the normal state every time your PC boots.

If a script trusts the port sitting in the log at that moment, it hands qBittorrent a dead port from your last session, and nothing tells you it went wrong. This one checks the tunnel is actually up first.

**2. When you disconnect, the Proton VPN network adapter doesn't go to "Down". It disappears from Windows completely.**

A check written the obvious way would decide you were still connected. This one reads the log as a second opinion.

## One thing that isn't documented anywhere

qBittorrent 5.x won't open its Web UI if no password has ever been set. Not even with the localhost login bypassed.

Setting `WebUI\Enabled=true` on its own leaves port 8080 shut, and nothing in any log tells you why.

If you followed another guide that said "turn on the Web UI and bypass localhost auth" and it just didn't work, that's why. This adds a random password when there isn't one. A password you set yourself is never touched or read.

## Requirements

- Proton VPN for Windows, with port forwarding turned on in its settings
- qBittorrent
- PowerShell 5.1, which is already on every Windows 10 and 11 machine

### What I actually tested it on

Being specific, because "should work" and "was tested" aren't the same thing.

| | Tested on |
|---|---|
| Windows | 11 Pro, build 26200 |
| PowerShell | 5.1.26100 |
| qBittorrent | 5.1.0 |
| Proton VPN | 4.4.1 |

Windows 10 is probably fine, nothing here uses anything Windows 11 only, but I haven't run it there so I'm not going to say it works.

Same with other qBittorrent versions. The Web API it uses (`/api/v2`) has been stable for years, but 5.1.0 is what I proved. If you try it somewhere else, an issue saying it worked or didn't is useful.

## Building the exe yourself

The exe is just the script compiled with [PS2EXE](https://github.com/MScholtes/PS2EXE), so you don't have to take my word for what's in it:

```powershell
Install-Module ps2exe -Scope CurrentUser
powershell -ExecutionPolicy Bypass -File Build-ProtonPortSync.ps1
```

That builds the icon from the logo, compiles the exe, and copies it to your Desktop.

## "Windows protected your PC"

The exe isn't code signed. Certificates cost a few hundred a year and this is free.

Click More info, then Run anyway. Or just run the `.ps1` instead. The full source is in this repo, which is the point.

## Support this

If it saved you some hassle you can [buy me a coffee on Ko-fi](https://ko-fi.com/omv421). Totally optional, the tool is free and always will be.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-tip-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/omv421)

## Licence

MIT, see [LICENSE](LICENSE). Do what you want with it.

Uses [PS2EXE](https://github.com/MScholtes/PS2EXE) by Markus Scholtes, also MIT, to build the exe.

Not affiliated with Proton AG or the qBittorrent project. It just works with them.
