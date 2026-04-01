#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="/tmp/cmux-release"
DROPBOX_DIR="$HOME/Dropbox"

cd "$PROJECT_DIR"

echo "==> Building release..."
CMUX_SKIP_ZIG_BUILD=1 xcodebuild \
  -project GhosttyTabs.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  build 2>&1 | tail -3

APP_PATH="$DERIVED_DATA/Build/Products/Release/cmux.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: cmux.app not found at $APP_PATH"
  exit 1
fi

echo "==> Zipping..."
ZIP_PATH="$DROPBOX_DIR/cmux.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
echo "==> Done! $ZIP_PATH ($SIZE)"
