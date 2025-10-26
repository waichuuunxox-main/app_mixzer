#!/usr/bin/env zsh
# deploy_apprunner_versioned.sh
# Usage: ./deploy_apprunner_versioned.sh <path-to-built-executable>
# Example: ./deploy_apprunner_versioned.sh .build/debug/AppRunner

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-built-executable>"
  exit 2
fi

BUILD_EXEC="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/AppRunner.app"
CONTENTS_MACOS="$DIST_APP/Contents/MacOS"
RESOURCES_DIR="$DIST_APP/Contents/Resources"
INFO_PLIST="$DIST_APP/Contents/Info.plist"

if [[ ! -f "$BUILD_EXEC" ]]; then
  echo "Error: built executable not found: $BUILD_EXEC"
  exit 3
fi

if [[ ! -d "$DIST_APP" ]]; then
  echo "Error: dist app bundle not found at $DIST_APP"
  exit 4
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERSION_NAME="AppRunner-v${TIMESTAMP}"
TARGET_PATH="$CONTENTS_MACOS/$VERSION_NAME"

# Backup existing dist bundle first (safe guard)
BACKUP_DIR="$ROOT_DIR/dist/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_NAME="AppRunner.app.backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating app backup: $BACKUP_DIR/$BACKUP_NAME"
/usr/bin/ditto "$DIST_APP" "$BACKUP_DIR/$BACKUP_NAME"

# If there are older backups located at dist/ (legacy created before we introduced backups dir),
# move them into the backups directory and make their executables non-executable to avoid
# accidentally launching an old bundle.
for legacy in "$ROOT_DIR/dist"/AppRunner.app.backup-*; do
  if [[ -e "$legacy" && ! -L "$legacy" ]]; then
    echo "Found legacy backup: $legacy -> moving to $BACKUP_DIR"
    /bin/mv "$legacy" "$BACKUP_DIR/" || true
    # try to remove executable bit of the contained executable to prevent accidental run
    if [[ -d "$BACKUP_DIR/$(basename "$legacy")/Contents/MacOS" ]]; then
      for f in "$BACKUP_DIR/$(basename "$legacy")/Contents/MacOS"/*; do
        if [[ -f "$f" ]]; then
          /bin/chmod a-x "$f" || true
        fi
      done
    fi
  fi
done

# Copy the new build into the bundle with versioned name
echo "Copying $BUILD_EXEC -> $TARGET_PATH"
/bin/cp "$BUILD_EXEC" "$TARGET_PATH"
/bin/chmod +x "$TARGET_PATH"

# Create or update a symlink named 'AppRunner' in Contents/MacOS that points to the versioned binary
SYMLINK_NAME="$CONTENTS_MACOS/AppRunner"
if [[ -L "$SYMLINK_NAME" || -e "$SYMLINK_NAME" ]]; then
  echo "Updating symlink $SYMLINK_NAME -> $VERSION_NAME"
  /bin/rm -f "$SYMLINK_NAME"
fi
ln -s "$VERSION_NAME" "$SYMLINK_NAME"

# Ensure Info.plist CFBundleExecutable equals the symlink name 'AppRunner'
if [[ -f "$INFO_PLIST" ]]; then
  CURRENT_EXEC=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || echo "")
  if [[ "$CURRENT_EXEC" != "AppRunner" ]]; then
    echo "Updating CFBundleExecutable in Info.plist to 'AppRunner'"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AppRunner" "$INFO_PLIST" || \
      /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string AppRunner" "$INFO_PLIST"
  fi
else
  echo "Warning: Info.plist not found at $INFO_PLIST. Skipping CFBundleExecutable update."
fi

# Record a VERSION file with timestamp + optional git info
mkdir -p "$RESOURCES_DIR"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
echo "VERSION=$TIMESTAMP" > "$RESOURCES_DIR/VERSION"
echo "COMMIT=$GIT_COMMIT" >> "$RESOURCES_DIR/VERSION"

# Make sure backups are not executable (safety net for the specific backup we just created)
if [[ -d "$BACKUP_DIR/$BACKUP_NAME/Contents/MacOS" ]]; then
  for bf in "$BACKUP_DIR/$BACKUP_NAME/Contents/MacOS"/*; do
    if [[ -f "$bf" ]]; then
      /bin/chmod a-x "$bf" || true
    fi
  done
fi

echo "Deployed version: $VERSION_NAME"
ls -l "$CONTENTS_MACOS" | sed -n '1,200p'

echo "Done."