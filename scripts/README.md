# scripts/ — Runner Management Scripts

## bootstrap.sh

Register and configure a new self-hosted runner with the VidiomTM org.

```bash
REGISTRATION_TOKEN=ghs_xxx ./scripts/bootstrap.sh ~/runners/mac-ci-7 mac-ci-7
```

Get a token:
```bash
# Org-level (registers runner visible to all org repos)
gh api -X POST orgs/VidiomTM/actions/runners/registration-token --jq .token

# Repo-level (registers runner visible to one repo)
gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token
```

After registration, install the launchd plist:
```bash
cp launchd/com.vidiomtm.runner.mac-ci-7.plist ~/Library/LaunchAgents/
launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.mac-ci-7.plist
```

## uninstall.sh

Unregister and remove a runner. Currently a placeholder — TODO: implement.

## healthcheck.sh

Local health check that reports:
- Total runners registered with the org
- Online/offline status
- Busy/idle status
- Local runner process state (via `pgrep`)
- Disk usage of `_work/` directories

```bash
./scripts/healthcheck.sh
```

Exits with code 1 if fewer runners are online than `$EXPECTED_RUNNERS`
(default: 5).
