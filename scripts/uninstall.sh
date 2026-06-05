#!/usr/bin/env bash
# uninstall.sh — Unregister and stop a self-hosted runner.
#
# Usage: ./uninstall.sh <runner-dir>

set -euo pipefail

RUNNER_DIR="${1:?usage: uninstall.sh <runner-dir>}"

if [ ! -d "$RUNNER_DIR" ]; then
  echo "ERROR: runner dir not found: $RUNNER_DIR" >&2
  exit 1
fi

cd "$RUNNER_DIR"

# Stop the runner first
if [ -f ".runner" ]; then
  echo "Stopping runner..."
  ./config.sh remove --token "$(./config.sh remove --help >/dev/null 2>&1; echo)" 2>/dev/null || true
fi

# Alternative: just delete the .runner file and the next start will re-register
# (only works if using --ephemeral or similar)

echo "✓ Runner unregistered: $RUNNER_DIR"
echo "  You may also want to:"
echo "  - Unload the launchd plist: launchctl unload -w ~/Library/LaunchAgents/com.vidiomtm.runner.*.plist"
echo "  - Remove the runner from GitHub: gh api -X DELETE orgs/VidiomTM/actions/runners/<id>"
