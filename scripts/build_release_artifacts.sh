#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NotesSyncApp"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app_bundle.sh"
DMG_SCRIPT="$ROOT_DIR/scripts/build_dmg.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  chmod +x "$BUILD_SCRIPT"
fi
if [[ ! -x "$DMG_SCRIPT" ]]; then
  chmod +x "$DMG_SCRIPT"
fi

"$BUILD_SCRIPT"
"$DMG_SCRIPT" --skip-build

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built artifacts:"
echo "- $DIST_DIR/${APP_NAME}-macOS.dmg"
echo "- $ZIP_PATH"
