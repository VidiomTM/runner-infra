# runner-infra

Self-hosted GitHub Actions runner infrastructure for the VidiomTM org.

## Problem

Without proper infrastructure, self-hosted runners:
- **Don't auto-start** after a reboot
- **Don't auto-restart** after a crash
- **Get stuck busy** when a job is cancelled, reducing capacity
- **Don't get monitored**, so failures go unnoticed

## Solution

Three pieces:

1. **launchd plists** (`launchd/`) — Auto-start on boot, auto-restart on crash
2. **Bootstrap script** (`scripts/bootstrap.sh`) — Register + configure new runners
3. **Health monitor workflow** (`workflows/monitor.yml`) — Cron-check capacity, alert on issues

Plus the existing [runner-hygiene](https://github.com/VidiomTM/runner-hygiene) action
cleans stale "busy" runners every 15 minutes.

## Architecture

```
┌─────────────────────────────────────────┐
│ GitHub Actions                          │
│  ┌─────────────────────┐                │
│  │ runner-monitor.yml  │ every 5 min    │
│  └──────────┬──────────┘                │
│             │                           │
│             │ alerts on < expected      │
│             ▼                           │
│  ┌─────────────────────┐                │
│  │ runner-hygiene      │ every 15 min   │
│  │ (VidiomTM/runner-   │                │
│  │  hygiene)           │                │
│  └──────────┬──────────┘                │
└─────────────┼───────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ macOS Host                              │
│                                         │
│  launchd                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐│
│  │ mac-ci   │ │ mac-ci-2 │ │ mac-ci-3 ││
│  │ plist    │ │ plist    │ │ plist    ││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘│
│       ▼             ▼             ▼     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐│
│  │Runner.   │ │Runner.   │ │Runner.   ││
│  │Listener  │ │Listener  │ │Listener  ││
│  └──────────┘ └──────────┘ └──────────┘│
│                                         │
│  Properties:                            │
│  - KeepAlive (restart on crash)         │
│  - RunAtLoad (start at boot)            │
│  - ThrottleInterval (no restart spam)   │
└─────────────────────────────────────────┘
```

## Quick Start

### 1. Install launchd plists

```bash
# Copy plists to ~/Library/LaunchAgents
cp launchd/com.vidiomtm.runner.*.plist ~/Library/LaunchAgents/

# Load them
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci.plist
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-2.plist
# ... etc

# Verify
launchctl list | grep vidiomtm
```

### 2. Register a new runner

```bash
# Get a registration token (requires org:admin)
export REGISTRATION_TOKEN=$(gh api -X POST orgs/VidiomTM/actions/runners/registration-token --jq .token)

# Register
./scripts/bootstrap.sh ~/runners/mac-ci-7 mac-ci-7
```

### 3. Install the monitor workflow

The monitor lives at `workflows/monitor.yml`. Copy it to `.github/workflows/` in this repo:

```bash
cp workflows/monitor.yml .github/workflows/monitor.yml
git add .github/workflows/monitor.yml
git commit -m "chore: install runner monitor"
```

Set the required variables in repo settings → Secrets and variables → Actions → Variables:
- `ORG_NAME` (default: `VidiomTM`)
- `EXPECTED_RUNNERS` (default: `5`)
- `MIN_AVAILABLE` (default: `3`)
- `MONITOR_REPO` (default: `runner-infra`)

## Operations

### Check runner health

```bash
./scripts/healthcheck.sh
```

### Add a new runner

1. Download the runner:
   ```bash
   mkdir -p ~/runners/mac-ci-N
   curl -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v2.319.1/actions-runner-osx-arm64-2.319.1.tar.gz
   tar xzf runner.tar.gz -C ~/runners/mac-ci-N
   ```

2. Register:
   ```bash
   REGISTRATION_TOKEN=$(gh api -X POST orgs/VidiomTM/actions/runners/registration-token --jq .token)
   ./scripts/bootstrap.sh ~/runners/mac-ci-N mac-ci-N
   ```

3. Add launchd plist:
   ```bash
   cp launchd/com.vidiomtm.runner.mac-ci-N.plist ~/Library/LaunchAgents/
   launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-N.plist
   ```

4. Update `EXPECTED_RUNNERS` variable in runner-infra repo settings.

### Remove a runner

```bash
launchctl unload ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-N.plist
rm ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-N.plist
rm -rf ~/runners/mac-ci-N
```

The runner will auto-unregister on shutdown (via `./config.sh remove` in the plist's pre-shutdown hook, if configured).

### Debug a stuck runner

```bash
# Check if it's actually running
launchctl list | grep vidiomtm

# Check the log
tail -100 ~/runners/mac-ci-N/runner.log

# Force restart
launchctl kickstart -k gui/$(id -u)/com.vidiomtm.runner.mac-ci-N

# Check GitHub side
gh api orgs/VidiomTM/actions/runners --jq '.runners[] | {name, status, busy}'
```

## Best Practices Applied

- **launchd KeepAlive.Crashed=true** — Restarts on crash
- **launchd KeepAlive.SuccessfulExit=false** — Doesn't restart on clean exit (allows manual stop)
- **launchd RunAtLoad=true** — Starts on boot/login
- **ThrottleInterval=10s** — Avoids restart spam
- **ProcessType=Background** — Low system priority
- **StandardOutPath/StandardErrorPath** — Logs to file for debugging
- **Cron health check** — Detects capacity issues within 5 minutes
- **Auto-clean stale** — runner-hygiene removes stuck-busy runners every 15 min
- **Alert via Issue** — Monitor creates a tracking issue when capacity drops

## References

- [runner-hygiene](https://github.com/VidiomTM/runner-infra) — Stale runner cleanup
- [GitHub: About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [Apple: launchd.plist](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
