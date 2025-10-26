#!/usr/bin/env zsh
# open_latest_apprunner.sh
# Safely open the latest deployed AppRunner via the symlink in dist/AppRunner.app

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/AppRunner.app"

if [[ ! -d "$DIST_APP" ]]; then
  echo "Error: dist App bundle not found at $DIST_APP"
  exit 1
fi

# Use 'open' which will launch the bundle in Finder/GUI; this opens the app pointed by CFBundleExecutable
open "$DIST_APP"

echo "Launched latest AppRunner: $DIST_APP"
