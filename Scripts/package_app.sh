#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LGVolume"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(tr -d '[:space:]' < BUILD_NUMBER)"
BUILD_CONFIGURATION="release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

swift build -c "$BUILD_CONFIGURATION" --arch arm64 -Xswiftc -Osize

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/arm64-apple-macosx/$BUILD_CONFIGURATION/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
for localization in Resources/*.lproj; do
  if [[ -d "$localization" ]]; then
    cp -R "$localization" "$RESOURCES_DIR/"
  fi
done
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

chmod +x "$MACOS_DIR/$APP_NAME"
strip -x "$MACOS_DIR/$APP_NAME"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Packaged $APP_BUNDLE"
