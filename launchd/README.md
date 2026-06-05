# launchd/ — Runner Service Definitions

Each `com.vidiomtm.runner.<name>.plist` is a launchd job that:
- Auto-starts the runner on system boot/login
- Auto-restarts on crash
- Logs to `~/runners/<name>/runner.log`
- Throttles restart attempts to once every 10 seconds

## Naming Convention

`com.vidiomtm.runner.<runner-name>` where `<runner-name>` matches the directory
under `~/runners/` (e.g., `mac-ci`, `mac-ci-2`, `mac-ci-3`).

## Installation

```bash
# Copy to user's LaunchAgents
cp com.vidiomtm.runner.*.plist ~/Library/LaunchAgents/

# Load (auto-start now + at boot)
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci.plist

# Verify
launchctl list | grep vidiomtm
```

## Properties Explained

| Key | Value | Why |
|---|---|---|
| `RunAtLoad` | `true` | Auto-start on boot/login |
| `KeepAlive.Crashed` | `true` | Restart after crash |
| `KeepAlive.SuccessfulExit` | `false` | Don't restart on clean exit (allows manual stop) |
| `ThrottleInterval` | `10` (seconds) | Avoid restart spam if it keeps crashing |
| `ProcessType` | `Background` | Low system priority |
| `Nice` | `5` | Slightly lower CPU priority than foreground |
| `StandardOutPath` | `~/runners/<name>/runner.log` | Captures stdout for debugging |
| `StandardErrorPath` | `~/runners/<name>/runner.log` | Captures stderr for debugging |

## Management

```bash
# Start a runner
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-2.plist

# Stop a runner (and prevent restart at boot)
launchctl unload -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-2.plist

# Restart a runner
launchctl kickstart -k gui/$(id -u)/com.vidiomtm.runner.mac-ci-2

# Check status
launchctl list | grep vidiomtm

# View logs
tail -f ~/runners/mac-ci-2/runner.log
```

## Why launchd, not systemd?

This is macOS — `launchd` is the native service manager. `systemd` is Linux-only.

## Why not use `svc.sh install`?

The runner ships with `./svc.sh install` which installs a launchd plist, but:
- It uses a generic label (`actions.runner.*`)
- It doesn't use `KeepAlive.Crashed` (it uses `KeepAlive=true` which restarts on any exit)
- The plist is harder to find/manage

Our plists are:
- Named consistently (`com.vidiomtm.runner.<name>`)
- Configurable per-runner
- Tracked in this repo for visibility
