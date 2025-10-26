#!/usr/bin/env zsh
# run_and_deploy_apprunner.sh
# Builds the project, deploys a versioned AppRunner into dist, and opens the app.
# Usage: ./scripts/run_and_deploy_apprunner.sh [debug|release]

set -euo pipefail
MODE=${1:-debug}
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_PATH="$ROOT_DIR/.build/arm64-apple-macosx/${MODE}/AppRunner"
DEPLOY_SCRIPT="$ROOT_DIR/scripts/deploy_apprunner_versioned.sh"

if [[ "$MODE" != "debug" && "$MODE" != "release" ]]; then
  echo "Invalid mode: $MODE. Use 'debug' or 'release'."
  exit 2
fi

echo "Building AppRunner ($MODE)..."
swift build -c ${MODE}

if [[ ! -f "$BUILD_PATH" ]]; then
  echo "Built executable not found at: $BUILD_PATH"
  exit 3
fi

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
  echo "Deploy script not found: $DEPLOY_SCRIPT"
  exit 4
fi

# Run deploy script (it expects the built executable path)
# Use zsh invocation that tolerates no-match legacy backups
zsh -o nonomatch -c '"$DEPLOY_SCRIPT" "$BUILD_PATH"'

# Open the deployed app bundle
open "$ROOT_DIR/dist/AppRunner.app"

echo "Launched versioned AppRunner from dist/AppRunner.app"
