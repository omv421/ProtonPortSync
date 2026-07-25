# ProtonPortSync

**Keeps qBittorrent's listening port matched to the port Proton VPN forwards you — in under a second, without restarting qBittorrent.**

Double-click it. That's the whole thing.

<p align="center">
  <img src="ProtonVPN_qBittorrent_Logo.png" width="180" alt="ProtonPortSync">
</p>

---

## The problem

Proton VPN gives you a forwarded port so people can connect to you. That port **changes** every time you reconnect. qBittorrent doesn't know it changed, so it sits listening on a dead port and your speeds quietly fall off a cliff.

Proton VPN on Windows has no command line, so there's nothing official to hook into.

## What this does

1. Makes sure Proton VPN is running and actually connected.
2. Reads the forwarded port out of Proton VPN's own log.
3. Puts that port into qBittorrent — **live, without restarting it**.

## Why not just restart qBittorrent?

Because restarting means every torrent stops, re-checks, and reconnects. This talks to qBittorrent's Web API instead, so nothing is interrupted. Torrents keep seeding while the port changes underneath them.

If the Web API isn't reachable for some reason, it falls back to editing the settings file and restarting — so it always works, it's just slower.

## Speed

Measured on a real machine, not estimated:

| Situation | Time |
|---|---|
| VPN connected, port changed | **0.7s** — no restart |
| VPN connected, port already right | **0.2s** — does nothing |
| qBittorrent closed | **0.9s** — starts it with the right port |
| Proton VPN open but not connected | waits for you, then **~8s** after you click Connect |
| Proton VPN closed | **~6s** — starts it and waits |

## What it copes with

| Situation | What happens |
|---|---|
| Proton VPN closed | Starts it, waits for it to connect |
| Proton VPN open but **not connected** | Opens its window so you can press Connect, then carries on by itself |
| qBittorrent closed | Starts it with the correct port already set |
| qBittorrent running | Changes the port live, no restart |
| Port already correct | Notices and does nothing |
| Proton VPN never connects | Says so plainly and changes nothing |

That fourth-from-last row matters more than it looks — see *Two things about Proton VPN* below.

## Install

1. Download **`ProtonPortSync.exe`**
2. Double-click it

There is no step 3. No Task Scheduler, no config file to edit, no renaming your network adapter, no enabling anything by hand.

Prefer to run the script directly? `ProtonPortSync.ps1` is the same program:

```powershell
powershell -ExecutionPolicy Bypass -File ProtonPortSync.ps1
```

### First run

The first run switches on qBittorrent's Web UI, because that's what allows the port to change without a restart. It's set to **this PC only**:

```
WebUI\Enabled         = true
WebUI\Address         = 127.0.0.1     <- not reachable from anywhere else
WebUI\LocalHostAuth   = false         <- no login needed from this PC
WebUI\Password_PBKDF2 = <random>
```

Your settings file is backed up to `qBittorrent.ini.bak` first. To undo it: qBittorrent → Tools → Options → Web UI → untick. Or run with `-NoWebUiSetup` and it won't touch those at all.

## Options

You don't need any of these. They're here if you want them.

| Option | What it does |
|---|---|
| `-Watch` | Stay running and re-sync automatically whenever the port changes. Ctrl+C to stop. |
| `-DryRun` | Show what it *would* change. Changes nothing, starts nothing. |
| `-Force` | Apply the port even if it already looks correct. |
| `-NoRestart` | Never restart qBittorrent, Web UI only. |
| `-NoWebUiSetup` | Don't touch the Web UI settings. |
| `-PortOnly` | Just find and print the port. Doesn't touch qBittorrent. |
| `-TimeoutSeconds` | How long to wait for a port. Default 90. |

## Two things about Proton VPN that shaped this

Both were found by testing, and both are the reason this handles some cases that other scripts don't.

**1. Proton VPN 4.4.1 has no auto-connect.** It starts with Windows, but it starts *disconnected*. So "open but not connected" isn't a rare edge case — it's the normal state every time your PC boots. If a script trusts the port sitting in the log at that moment, it will hand qBittorrent a **dead port** from your last session, with no error at all. This one checks the tunnel is genuinely up first.

**2. When you disconnect, the Proton VPN network adapter doesn't switch to "Down" — it disappears from Windows entirely.** A check written the obvious way would conclude you were still connected. This one also reads the log as a second opinion.

## One thing that isn't documented anywhere

**qBittorrent 5.x refuses to open its Web UI when no password has ever been set** — even with the localhost login bypassed. Setting `WebUI\Enabled=true` on its own leaves port 8080 shut, and *nothing in any log says why*.

If you've followed another guide that says "enable the Web UI and bypass localhost auth" and it silently didn't work, that's why. This tool adds a random password automatically when none exists. A password you set yourself is never touched or read.

## Requirements

- Windows 10 or 11
- Proton VPN (Windows app) with **port forwarding switched on** in its settings
- qBittorrent (tested on 5.1)
- PowerShell 5.1 — already on every Windows machine

## Building the exe yourself

The exe is just the script compiled with [PS2EXE](https://github.com/MScholtes/PS2EXE), so you never have to take my word for what's inside it:

```powershell
Install-Module ps2exe -Scope CurrentUser
powershell -ExecutionPolicy Bypass -File Build-ProtonPortSync.ps1
```

That builds the icon from the logo, compiles the exe, and copies it to your Desktop.

## "Windows protected your PC"

The exe isn't code-signed — certificates cost a few hundred a year and this is free. Click **More info → Run anyway**, or just run the `.ps1` instead. The full source is right here in this repo, which is rather the point.

## Support this

If it saved you some annoyance, you can [buy me a coffee](ADD_YOUR_LINK_HERE). Entirely optional — the tool is free and always will be.

## Licence

MIT — see [LICENSE](LICENSE). Do what you like with it.

Uses [PS2EXE](https://github.com/MScholtes/PS2EXE) by Markus Scholtes (also MIT) to build the exe.

Not affiliated with Proton AG or the qBittorrent project. Just works with them.
