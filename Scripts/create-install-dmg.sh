#!/usr/bin/env bash
# Build a classic macOS installer DMG: app on the left, Applications drop-target on the right.
#
# Usage:
#   Scripts/create-install-dmg.sh <path-to-cues.live.app> <output.dmg> [volume-name]
#
# Requires: create-dmg (brew install create-dmg)

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <cues.live.app> <output.dmg> [volume-name]" >&2
  exit 1
fi

APP_PATH="$1"
OUTPUT_DMG="$2"
VOLUME_NAME="${3:-cues.live}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/cues-live-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE/$APP_NAME"

# create-dmg refuses to overwrite; remove any leftover from a failed run.
rm -f "$OUTPUT_DMG"

mkdir -p "$(dirname "$OUTPUT_DMG")"

# Window layout matches the usual “drag to Applications” installer.
# create-dmg exits 2 when Finder finishes with a benign blessing warning.
set +e
create-dmg \
  --volname "$VOLUME_NAME" \
  --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "$APP_NAME" 160 180 \
  --hide-extension "$APP_NAME" \
  --app-drop-link 480 180 \
  --no-internet-enable \
  "$OUTPUT_DMG" \
  "$STAGE"
STATUS=$?
set -e

if [[ ! -f "$OUTPUT_DMG" ]]; then
  echo "create-dmg failed (exit $STATUS) and produced no DMG" >&2
  exit "$STATUS"
fi

if [[ "$STATUS" -ne 0 && "$STATUS" -ne 2 ]]; then
  echo "create-dmg failed with exit $STATUS" >&2
  exit "$STATUS"
fi

echo "Created $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
