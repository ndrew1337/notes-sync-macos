#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NotesSyncApp"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app_bundle.sh"
DIST_APP="$ROOT_DIR/dist/${APP_NAME}.app"
USER_APPS_DIR="$HOME/Applications"
TARGET_APP="$USER_APPS_DIR/${APP_NAME}.app"

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  chmod +x "$BUILD_SCRIPT"
fi

# Best effort: close running app before replacing bundle files.
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
sleep 0.5

"$BUILD_SCRIPT"

if [[ ! -d "$DIST_APP" ]]; then
  echo "Build output missing: $DIST_APP" >&2
  exit 1
fi

mkdir -p "$USER_APPS_DIR"
rm -rf "$TARGET_APP"
cp -R "$DIST_APP" "$TARGET_APP"

open "$TARGET_APP"
echo "Updated and launched: $TARGET_APP"
