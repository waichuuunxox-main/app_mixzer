#!/usr/bin/env bash
# Quick guard: ensure the declared 35% / 65% multipliers and spacing=0 remain in RankingsView.swift
# Exit 0 if all checks pass; non-zero if failure.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT_DIR/Sources/app_mixzer/RankingsView.swift"

if [ ! -f "$FILE" ]; then
  echo "ERROR: RankingsView.swift not found at expected path: $FILE" >&2
  exit 2
fi

# Check for the literal multipliers (0.35 and 0.65) used in frame(width: geo.size.width * 0.35) etc.
GREP35=$(grep -n "geo.size.width *\* *0.35" "$FILE" || true)
GREP65=$(grep -n "geo.size.width *\* *0.65" "$FILE" || true)
GREPSPACING=$(grep -n "HStack(spacing: 0)" "$FILE" || true)

if [ -z "$GREP35" ] || [ -z "$GREP65" ] || [ -z "$GREPSPACING" ]; then
  echo "LAYOUT CONTRACT VIOLATION:" >&2
  echo " - geo.size.width * 0.35 present: ${GREP35:-MISSING}" >&2
  echo " - geo.size.width * 0.65 present: ${GREP65:-MISSING}" >&2
  echo " - HStack(spacing: 0) present: ${GREPSPACING:-MISSING}" >&2
  exit 1
fi

# All checks passed
echo "Layout contract check: OK"
exit 0
