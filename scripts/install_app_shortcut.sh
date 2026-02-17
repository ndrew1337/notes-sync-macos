#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NotesSyncApp"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/${APP_NAME}.app"
USER_APPS_DIR="$HOME/Applications"
TARGET_APP="$USER_APPS_DIR/${APP_NAME}.app"
LAUNCHER_APP="$USER_APPS_DIR/${APP_NAME} Launcher.app"
LAUNCHER_BIN="$LAUNCHER_APP/Contents/MacOS/launch_notes_sync"
LAUNCHER_PLIST="$LAUNCHER_APP/Contents/Info.plist"
DESKTOP_LINK="$HOME/Desktop/${APP_NAME}.app"
UPDATE_SCRIPT="$ROOT_DIR/scripts/update_installed_app.sh"

if [[ ! -d "$DIST_APP" ]]; then
  echo "App bundle not found at: $DIST_APP"
  echo "Build it first with: ./scripts/build_app_bundle.sh"
  exit 1
fi

if [[ ! -x "$UPDATE_SCRIPT" ]]; then
  chmod +x "$UPDATE_SCRIPT"
fi

mkdir -p "$USER_APPS_DIR"
rm -rf "$TARGET_APP"
cp -R "$DIST_APP" "$TARGET_APP"

rm -rf "$LAUNCHER_APP"
mkdir -p "$LAUNCHER_APP/Contents/MacOS"
mkdir -p "$LAUNCHER_APP/Contents/Resources"

cat > "$LAUNCHER_BIN" <<LAUNCHER
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$ROOT_DIR"
UPDATE_SCRIPT="\$ROOT_DIR/scripts/update_installed_app.sh"
LOG_DIR="\$HOME/.notes-sync-app"
LOG_FILE="\$LOG_DIR/launcher.log"

mkdir -p "\$LOG_DIR"

{
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Launcher start"
  "\$UPDATE_SCRIPT"
  echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Launcher done"
} >> "\$LOG_FILE" 2>&1 || {
  /usr/bin/osascript -e "display alert \"NotesSyncApp\" message \"Update failed. See \$LOG_FILE\" as critical" >/dev/null 2>&1 || true
  exit 1
}
LAUNCHER
chmod +x "$LAUNCHER_BIN"

cat > "$LAUNCHER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>launch_notes_sync</string>
    <key>CFBundleIdentifier</key>
    <string>local.notes.sync.app.launcher</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME} Launcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$LAUNCHER_APP" >/dev/null 2>&1 || true

if [[ -L "$DESKTOP_LINK" || -e "$DESKTOP_LINK" ]]; then
  rm -rf "$DESKTOP_LINK"
fi
ln -s "$LAUNCHER_APP" "$DESKTOP_LINK"

echo "Installed app: $TARGET_APP"
echo "Installed auto-update launcher: $LAUNCHER_APP"
echo "Desktop shortcut: $DESKTOP_LINK"
echo "Use the desktop shortcut for auto-update on launch."
echo "You can also drag $LAUNCHER_APP to Dock for one-click launch."
