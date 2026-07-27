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

Proton VPN has an official CLI on Linux, but nothing on Windows. So there's nothing official to plug into, and reading the log is the only way in.

## What it does

1. Checks Proton VPN is running and actually connected.
2. Reads the forwarded port out of Proton VPN's log.
3. Puts that port into qBittorrent while it's still running.

## Why not just restart qBittorrent?

Restarting stops every torrent, then re-checks them, then reconnects. Takes ages.

This talks to qBittorrent's Web API instead. The process is never touched. I checked the process ID before and after, it's the same qBittorrent.

If the Web API isn't reachable it falls back to editing the settings file and restarting. So it always works, it's just slower.

## Other tools that do this

I'd rather link these than pretend I'm the only one. Pick whichever suits you.

### Quantum

[Quantum](https://github.com/UHAXM1/Quantum) is the established option and it's popular for good reason. Same idea as this one: it reads the Proton VPN log and pushes the port through qBittorrent's Web API. It's a .NET app you leave running.

What it does better: it's been around, it has a real user base, and it has had far more eyes on it than this.

The differences are in the setup and the shape. Quantum asks you to turn on qBittorrent's Web UI yourself and then type the host and login into it. This one does that for you and then finishes, in about a fifth of a second, rather than sitting in the background. If you'd rather have something running and watching, use Quantum, or use `-Watch` here.

One thing worth knowing whichever you pick: **if you have never set a Web UI password, qBittorrent won't open the Web UI at all**, and no log tells you why. Any tool that talks to the Web API is stuck until that's sorted. See the section further down.

I haven't tested how Quantum behaves when Proton VPN is open but disconnected, so I'm not claiming anything about it either way.

## What about gluetun?

[Gluetun](https://github.com/qdm12/gluetun) is good and you should use it if it fits. It is a different setup though, not a competing one.

Gluetun **is** the VPN client. It makes its own WireGuard or OpenVPN connection inside a Docker container, so you are not running the Proton VPN Windows app at all, and qBittorrent has to run in Docker too on gluetun's network.

It also sets qBittorrent's port on its own, with no extra script or container. Its `VPN_PORT_FORWARDING_UP_COMMAND` setting runs whenever the port changes and posts straight to the same qBittorrent API this tool uses.

Being straight about it: if your stack is already in Docker, gluetun is the better answer. It asks Proton's API properly instead of reading a log file, and log formats change without warning.

This is for the other case. You run the normal Proton VPN desktop app, you have a normal qBittorrent install, and you are not going to containerise your torrent client over a port number.

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

## "It keeps giving me the same port, it's not refreshing"

That's Proton, and it is not a fault. Reconnect quickly and you get your old port straight back.

Here is a real log, five disconnect and reconnect cycles inside two minutes:

```
16:26:32   (none)  ->  53992     connected to US-WA#445
16:27:45   53992   ->  (none)    disconnected
16:27:48   (none)  ->  53992     connected to US-WA#445
16:27:53   53992   ->  (none)    disconnected
16:27:57   (none)  ->  53992     connected to US-WA#445
16:28:02   53992   ->  (none)    disconnected
16:28:03   (none)  ->  53992     connected to US-WA#445
16:28:11   53992   ->  (none)    disconnected
16:28:24   (none)  ->  53992     connected to US-WA#445
```

Same server, same port, every time. The port really does drop to nothing while you are disconnected, and Proton hands the identical one back.

What is actually measured, from two days of logs:

| gap while disconnected | port came back |
|---|---|
| 1.3s | same |
| 2.7s | same |
| 3.8s | same |
| 13.3s | same |
| **14.9 minutes** | **different** (53992 to 40547) |
| 22.8 hours | different |

So short reconnects keep your port, and a long enough gap gets you a new one. **Where the boundary sits is still not known**, but it is somewhere between 13 seconds and 15 minutes. Not precise, and far better than a guess.

Proton's log does say the mapping is `expiring in 00:01:00`, and while you are connected it visibly refreshes on that cadence. It is tempting to conclude a 60 second disconnect loses your port. The data here does not show that, so this README is not going to claim it.

**Nothing needs fixing when this happens.** A port that has not changed is the good case. The tool notices, says it is already correct, and exits in about 0.2 seconds without touching qBittorrent.

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

## Running it automatically at login

Optional. If you'd rather never click it:

```powershell
powershell -ExecutionPolicy Bypass -File Install-AtLogin.ps1
```

To undo that, same command with `-Remove`.

**It does not just run and give up.** That would be useless here, and the reason is the first Proton VPN quirk further down: Proton launches itself at login but launches *disconnected*, so at that moment there is no tunnel and no port, and there won't be one until you press Connect.

So instead it starts hidden and **waits up to 30 minutes** for you to connect. The moment you do, it syncs the port and exits. If you never connect, it leaves quietly having done nothing and without logging an error, because choosing not to use the VPN today isn't a fault.

While it's waiting it stays out of your way. It won't throw Proton's window across your screen the way a manual run does, because Proton deliberately starts minimised to the tray and overriding that on every single boot is obnoxious.

Only one copy runs at a time, so logging out and back in won't stack them up.

No window ever appears. To see what it did, open `%TEMP%\vpn_qbittorrent_log.txt`.

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

**1. Proton VPN starts up disconnected unless you go and switch auto-connect on, and the setting is easy to miss.**

It lives at **Settings → General → Auto-startup → Auto-connect**, nested under the auto-startup option rather than sitting on its own. It is off by default.

So out of the box, "the app is open but not connected" is the normal state every time your PC boots, not a rare case.

If a script trusts the port sitting in the log at that moment, it hands qBittorrent a dead port left over from your last session, and nothing tells you it went wrong. This one checks the tunnel is actually up first.

> **Correction, 2026-07-26.** This section previously said version 4.4.1 has no auto-connect at all. That was wrong twice over. The version is 5.1.5, and it does have auto-connect. The mistake came from searching an old `v4.4.1` folder that Proton had left behind after updating, and taking the first result without checking whether there was more than one. The behaviour described above is real and was the reason for the design. The explanation for it was not.

**2. When you disconnect, the Proton VPN network adapter doesn't go to "Down". It disappears from Windows completely.**

A check written the obvious way would decide you were still connected. This one reads the log as a second opinion.

## One thing that isn't documented anywhere

qBittorrent won't open its Web UI if no password has ever been set. Not even with the localhost login bypassed.

Measured on 5.1.0. It probably applies across 5.x, but 5.1.0 is the one I actually proved, so that's what I'll claim.

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
| Proton VPN | 5.1.5 |

Windows 10 is probably fine, nothing here uses anything Windows 11 only, but I haven't run it there so I'm not going to say it works.

Same with other qBittorrent versions. The Web API it uses (`/api/v2`) has been stable for years, but 5.1.0 is what I proved. If you try it somewhere else, an issue saying it worked or didn't is useful.

## Building the exe yourself

The exe is just the script compiled with [PS2EXE](https://github.com/MScholtes/PS2EXE) (Microsoft Limited Public License 1.1, see [NOTICE](NOTICE)), so you don't have to take my word for what's in it:

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

My code is MIT, see [LICENSE](LICENSE). Fork it, change it, sell it, whatever. Just keep the copyright line.

The exe is built with [PS2EXE](https://github.com/MScholtes/PS2EXE) by Markus Scholtes, which is **not** MIT. It's the Microsoft Limited Public License 1.1, and that carries a Windows-only restriction MIT doesn't have. Doesn't change anything here since this is a Windows-only tool, but it's worth stating correctly. Details in [NOTICE](NOTICE).

If you only want MIT code, skip the exe and run `ProtonPortSync.ps1`. That's the whole program, it's MIT, and no PS2EXE code is involved.

Not affiliated with Proton AG or the qBittorrent project. It just works with them.
