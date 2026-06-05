#!/usr/bin/env bash
# bootstrap.sh — Register a new self-hosted runner with the VidiomTM org.
#
# Usage: REGISTRATION_TOKEN=ghs_xxx ./bootstrap.sh <runner-dir> <runner-name>
#
# Get a token:
#   gh api -X POST orgs/VidiomTM/actions/runners/registration-token --jq .token
#
# Or for a single repo:
#   gh api -X POST repos/OWNER/REPO/actions/runners/registration-token --jq .token

set -euo pipefail

RUNNER_DIR="${1:?usage: bootstrap.sh <runner-dir> <runner-name>}"
RUNNER_NAME="${2:?usage: bootstrap.sh <runner-dir> <runner-name>}"
ORG="${ORG:-VidiomTM}"
LABELS="${LABELS:-self-hosted,macOS,ARM64,VidiomTM}"
TOKEN="${REGISTRATION_TOKEN:?set REGISTRATION_TOKEN env var}"

if [ ! -d "$RUNNER_DIR" ]; then
  echo "ERROR: runner dir not found: $RUNNER_DIR" >&2
  echo "  Download runner: https://github.com/actions/runner/releases" >&2
  echo "  tar xzf actions-runner-osx-arm64-X.Y.Z.tar.gz -C $RUNNER_DIR" >&2
  exit 1
fi

if [ ! -x "$RUNNER_DIR/config.sh" ]; then
  echo "ERROR: $RUNNER_DIR/config.sh not executable" >&2
  exit 1
fi

cd "$RUNNER_DIR"

# If a .runner file already exists, the runner is already registered.
# Use --replace to overwrite the registration with the new name.
if [ -f ".runner" ]; then
  echo "Existing registration found; replacing..."
  REPLACE_FLAG="--replace"
else
  REPLACE_FLAG=""
fi

./config.sh --unattended $REPLACE_FLAG \
  --url "https://github.com/$ORG" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$LABELS" \
  --work "_work" \
  --runasservice

echo ""
echo "✓ Runner registered: $RUNNER_NAME"
echo "  Start it with: cd $RUNNER_DIR && ./run.sh"
echo "  Or load the launchd plist: launchctl load -w ~/Library/LaunchAgents/com.vidiomtm.runner.${RUNNER_NAME}.plist"
