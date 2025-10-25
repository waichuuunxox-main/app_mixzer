#!/usr/bin/env bash
set -euo pipefail

# generate_and_open_xcode.sh
# 產生 Swift Package 的 Xcode 專案並開啟第一個 .xcodeproj

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

echo "Generating Xcode project in $repo_root..."
swift package generate-xcodeproj

proj=$(ls *.xcodeproj 2>/dev/null | head -n 1 || true)
if [[ -z "$proj" ]]; then
  echo "No .xcodeproj found"
  exit 1
fi

echo "Opening $proj ..."
open "$proj"

echo "Done."
