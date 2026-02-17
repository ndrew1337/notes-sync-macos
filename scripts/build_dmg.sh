#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NotesSyncApp"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app_bundle.sh"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
STAGING_DIR="$DIST_DIR/.dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-macOS.dmg"
SKIP_BUILD=0

if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=1
fi

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  chmod +x "$BUILD_SCRIPT"
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  "$BUILD_SCRIPT"
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "Built DMG: $DMG_PATH"
