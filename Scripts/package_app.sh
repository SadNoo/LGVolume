#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LGVolume"
BUILD_CONFIGURATION="release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c "$BUILD_CONFIGURATION" --arch arm64

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/arm64-apple-macosx/$BUILD_CONFIGURATION/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Packaged $APP_BUNDLE"
