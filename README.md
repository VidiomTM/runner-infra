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

1. **launchd-managed ephemeral-manager** — Auto-start on boot, auto-restart on crash, automatic re-registration cycle
2. **Bootstrap script** (`scripts/bootstrap.sh`) — Register + configure new runners
3. **Health monitor workflow** (`workflows/monitor.yml`) — Cron-check capacity, alert on issues

Plus the existing [runner-hygiene](https://github.com/VidiomTM/runner-hygiene) action
cleans stale "busy" runners every 15 minutes.

### Existing setup (already in place)

The VidiomTM org has 8 runner slots pre-configured (`mac-ci` through `mac-ci-8`).
Each has a launchd plist at `~/Library/LaunchAgents/actions.runner.VidiomTM.ephemeral.mac-ci-N.plist`
that wraps `ephemeral-manager.sh` with the canonical pattern:

```xml
<key>ProgramArguments</key>
<array>
  <string>/Users/jonathangadeaharder/runners/mac-ci-N/ephemeral-manager.sh</string>
  <string>/Users/jonathangadeaharder/runners/mac-ci-N</string>
  <string>mac-ci-N</string>
</array>
<key>UserName</key><string>jonathangadeaharder</string>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>5</integer>
<key>SessionCreate</key><true/>
<key>EnvironmentVariables</key>
<dict><key>ACTIONS_RUNNER_SVC</key><string>1</string></dict>
<key>ProcessType</key><string>Interactive</string>
```

**Key points:**
- `KeepAlive: true` (not just `Crashed`) — restart on any exit, including the manager's intentional restarts between cycles
- `SessionCreate: true` — gives the runner access to the user session (keychain, GUI tools)
- `ACTIONS_RUNNER_SVC=1` — tells the runner it's running as a service
- `ThrottleInterval: 5` — bounded restart rate even if the manager crashes in a loop

The plists in `launchd/` here are reference templates — use them when adding a new runner slot.

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

### 1. Install launchd plists (new runner)

For a new runner, copy the plist template and load it:

```bash
# Copy the template
cp launchd/com.vidiomtm.runner.mac-ci-N.plist ~/Library/LaunchAgents/

# Load
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-N.plist

# Verify
launchctl list | grep vidiomtm
```

**Note:** Existing runners (`mac-ci` through `mac-ci-6`) already have plists at
`~/Library/LaunchAgents/actions.runner.VidiomTM.ephemeral.mac-ci-N.plist`.
Do NOT duplicate — pick one label and use it. The reference plists in this repo
are for documentation/audit; the originals have the same content plus the
`SessionCreate` and `ACTIONS_RUNNER_SVC` keys that are critical for runners.

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
# Unload the launchd plist (existing or new label)
LABEL="actions.runner.VidiomTM.ephemeral.mac-ci-N"  # or com.vidiomtm.runner.mac-ci-N
launchctl unload ~/Library/LaunchAgents/${LABEL}.plist
rm ~/Library/LaunchAgents/${LABEL}.plist

# Remove the runner dir (config.sh runs to unregister)
rm -rf ~/runners/mac-ci-N
```

The runner will auto-unregister on shutdown (via `./config.sh remove` in the plist's pre-shutdown hook, if configured).

### Debug a stuck runner

```bash
# Check if launchd is managing it
launchctl list | grep -E "actions.runner.VidiomTM|vidiomtm"

# Check the manager process
ps -axo pid,ppid,etime,command | grep ephemeral-manager | grep mac-ci-N

# Check the listener process
ps -axo pid,ppid,etime,command | grep mac-ci-N/bin/Runner.Listener

# Check logs
tail -50 ~/runners/mac-ci-N/_diag/ephemeral-manager.log
tail -50 ~/runners/mac-ci-N/_diag/Runner_$(ls -t ~/runners/mac-ci-N/_diag/Runner_*.log | head -1 | xargs basename | sed 's/Runner_//;s/.log//')

# Check GitHub side
gh api orgs/VidiomTM/actions/runners --jq '.runners[] | {name, status, busy}'

# Force restart the manager (launchd will restart it)
launchctl kill SIGTERM gui/$(id -u)/actions.runner.VidiomTM.ephemeral.mac-ci-N

# Force restart the runner (let the manager cycle)
# Find the run.sh PID and kill it; the manager detects exit and re-registers
RUN_PID=$(pgrep -f "/runners/mac-ci-N/run.sh")
kill -TERM $RUN_PID
```

### Stuck on GitHub but listener is alive

This happens when the broker connection drops (host sleep, network blip, DNS hiccup).
The listener doesn't know it lost the connection until it tries to poll.

```bash
# Force the manager to cycle a new runner
RUN_PID=$(pgrep -f "/runners/mac-ci-N/run.sh")
kill -TERM $RUN_PID

# Manager detects exit, removes stale .runner, registers fresh agent with new name
# Wait ~30s for the new listener to appear in the API
gh api orgs/VidiomTM/actions/runners --jq '.runners[] | select(.name | contains("mac-ci-N")) | {name, status, busy}'
```

If the new listener also doesn't appear, the broker connection is genuinely broken
— check network, DNS, and GitHub status.

## How the self-healing cycle works

```
launchd → ephemeral-manager.sh → register → run.sh → Runner.Listener
                  ↑                                            │
                  │                                            ▼
                  └────────── re-register on exit ◄───── job done
```

`ephemeral-manager.sh` runs forever:
1. Get a fresh registration token from `gh api /orgs/VidiomTM/actions/runners/registration-token`
2. Run `config.sh --ephemeral` to register with a unique name
3. Run `run.sh` (which spawns `Runner.Listener`)
4. When `run.sh` exits (job done, crash, broker timeout, anything), clean up the `.runner` file and loop to step 1

**Why this beats plain `run.sh`:**
- Plain `run.sh` keeps the same agent registered, so if it crashes mid-job, GitHub sees the agent as "offline" until manual intervention.
- Ephemeral runners auto-remove themselves when `run.sh` exits (no cleanup needed).
- A new agent with a unique name registers fresh — no broker connection reuse, no stale state.

**What launchd adds:**
- Auto-start on boot (`RunAtLoad: true`)
- Auto-restart if the manager itself dies (`KeepAlive: true`)
- Throttle restarts to every 5s if something is in a tight crash loop

**What `runner-hygiene` adds:**
- Catches runners that go "offline" on GitHub's side but the listener is still alive locally (broker connection dropped, host suspend/resume, etc.)
- Polls the org API every 15 min, removes any runner whose `status != online` for > 1 hour

**What the monitor workflow adds:**
- Capacity alert: if the count of `online && !busy` runners drops below `MIN_AVAILABLE`, file an issue
- Runs every 5 min
- Dedupe: only one open alert at a time

## Best Practices Applied

- **launchd KeepAlive: true** — Restarts manager on any exit (crash, intentional stop, OOM)
- **launchd RunAtLoad: true** — Starts on boot/login
- **ThrottleInterval=5s** — Bounded restart rate even in tight crash loops
- **SessionCreate: true** — Runner gets user session (keychain, GUI tools)
- **ACTIONS_RUNNER_SVC=1** — Tells the runner it's a service
- **ephemeral-manager.sh** — Self-healing register/run/deregister cycle
- **--ephemeral flag** — Auto-cleanup, no manual unregister needed
- **Unique agent names** (`mac-ci-N-<timestamp>-<pid>`) — No name collisions on re-register
- **runner-hygiene** — Catches stuck-busy runners that the local manager can't detect
- **Cron health check** — Detects capacity issues within 5 minutes
- **Alert via Issue** — Monitor creates a tracking issue when capacity drops

## References

- [runner-hygiene](https://github.com/VidiomTM/runner-hygiene) — Stale runner cleanup
- [GitHub: About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [Apple: launchd.plist](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [GitHub: Actions Runner ephemeral](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#using-ephemeral-runners) — Why --ephemeral matters
