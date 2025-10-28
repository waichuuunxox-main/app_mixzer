#!/usr/bin/env zsh
# build_and_deploy_and_open.sh
# Build the Swift package (debug), then deploy the built AppRunner into dist and open the bundle.
# Usage: ./scripts/build_and_deploy_and_open.sh
set -euo pipefail
setopt null_glob

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_EXEC="$ROOT_DIR/.build/debug/AppRunner"
DEPLOY_SCRIPT="$ROOT_DIR/scripts/deploy_apprunner_versioned.sh"

echo "Building package (debug)..."
swift build -c debug

if [[ ! -f "$BUILD_EXEC" ]]; then
  echo "Error: expected built executable not found at $BUILD_EXEC"
  exit 2
fi

if [[ ! -x "$DEPLOY_SCRIPT" ]]; then
  echo "Making deploy script executable: $DEPLOY_SCRIPT"
  chmod +x "$DEPLOY_SCRIPT" || true
fi

# Call deploy script which itself will open the bundle when done
echo "Deploying and opening AppRunner..."
"$DEPLOY_SCRIPT" "$BUILD_EXEC"

# Optionally, verify the app process is running (give a short delay)
sleep 0.6
PG=$(pgrep -laf AppRunner || true)
if [[ -n "$PG" ]]; then
  echo "AppRunner processes found:" 
  echo "$PG"
else
  echo "Warning: no AppRunner process detected by pgrep; it may be running as a different process or opening is delayed." 
fi

echo "Done."
