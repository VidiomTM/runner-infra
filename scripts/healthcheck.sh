#!/usr/bin/env bash
# healthcheck.sh — Local health check for self-hosted runners.
#
# Reports:
# - Total runners registered with the org
# - Online/offline status
# - Busy/idle status
# - Last job completion time
# - Disk usage of _work directories
#
# Usage: ./healthcheck.sh
# Requires: gh (authenticated with org:admin)

set -euo pipefail

ORG="${ORG:-VidiomTM}"
RUNNERS_BASE="${RUNNERS_BASE:-$HOME/runners}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not installed" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh not authenticated" >&2
  exit 1
fi

echo "=== Runner Health Check ==="
echo "Org: $ORG"
echo "Runners base: $RUNNERS_BASE"
echo "Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo ""

# Fetch runners from API
runners=$(gh api "orgs/$ORG/actions/runners" --jq '.runners')

echo "=== GitHub-Registered Runners ==="
echo "$runners" | jq -r '.[] | "\(.name)\t\(.status)\tbusy=\(.busy)\t\(.os)"' | column -t -s$'\t' || true
echo ""

# Check local runners
echo "=== Local Runner Directories ==="
total_local=$(find "$RUNNERS_BASE" -maxdepth 1 -mindepth 1 -type d -name 'mac-ci*' | wc -l | tr -d ' ')
echo "Local runner dirs: $total_local"
echo ""

if [ "$total_local" -gt 0 ]; then
  echo "=== Local Process Status ==="
  for runner_dir in "$RUNNERS_BASE"/mac-ci*; do
    [ -d "$runner_dir" ] || continue
    name=$(basename "$runner_dir")
    if pgrep -f "$runner_dir.*Runner.Listener" >/dev/null 2>&1; then
      status="RUNNING"
    else
      status="STOPPED"
    fi
    disk=$(du -sh "$runner_dir/_work" 2>/dev/null | cut -f1 || echo "n/a")
    printf "  %-15s %-10s _work=%s\n" "$name" "$status" "$disk"
  done
fi

echo ""
echo "=== Summary ==="
online=$(echo "$runners" | jq '[.[] | select(.status == "online")] | length')
busy=$(echo "$runners" | jq '[.[] | select(.busy == true)] | length')
total=$(echo "$runners" | jq 'length')
expected="${EXPECTED_RUNNERS:-5}"

echo "Online: $online / $expected expected"
echo "Busy: $busy / $online online"
echo "Total registered: $total"

if [ "$online" -lt "$expected" ]; then
  echo ""
  echo "WARNING: $((expected - online)) runner(s) offline"
  exit 1
fi
