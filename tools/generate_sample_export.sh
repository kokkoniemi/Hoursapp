#!/usr/bin/env bash
# Regenerate docs/sample-export.xlsx — the example workbook shipped in the repo.
#
# Runs the gated SampleExportGenerator test in the HoursappTests target. The
# test is gated on a trigger file (xcodebuild test doesn't forward shell env
# vars), so this script creates the trigger, runs the test, then cleans up.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRIGGER="$ROOT/.sample-export-trigger"
OUT="$ROOT/docs/sample-export.xlsx"

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

cleanup() { rm -f "$TRIGGER"; }
trap cleanup EXIT

: > "$TRIGGER"

cd "$ROOT"

DEVELOPER_DIR="$DEVELOPER_DIR" \
  "$XCODEBUILD" \
    -project Hoursapp.xcodeproj \
    -scheme Hoursapp \
    -only-testing:HoursappTests/SampleExportGenerator \
    test \
  | tail -n 40

echo
echo "Wrote $OUT"
