#!/bin/zsh
# 編譯並組出 build/StandbyLock.app（release、ad-hoc 簽章）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=StandbyLock
BUNDLE_ID=com.david.standbylock
BUILD_DIR=build
APP="$BUILD_DIR/$APP_NAME.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
echo "Built: $APP"
