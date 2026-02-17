#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/scripts/build_app_bundle.sh"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install_app_shortcut.sh"

if [[ ! -x "$BUILD_SCRIPT" ]]; then
  chmod +x "$BUILD_SCRIPT"
fi

if [[ ! -x "$INSTALL_SCRIPT" ]]; then
  chmod +x "$INSTALL_SCRIPT"
fi

echo "Step 1/2: Build app bundle"
"$BUILD_SCRIPT"

echo "Step 2/2: Install app and desktop shortcut"
"$INSTALL_SCRIPT"

echo "Done."
