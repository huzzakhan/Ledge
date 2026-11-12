#!/bin/bash
# Builds Ledge.app and packs it into build/Ledge.dmg
#
#   bash Scripts/build-dmg.sh                      # build for this Mac
#   ARCHS="arm64 x86_64" bash Scripts/build-dmg.sh # universal (needs full Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Ledge"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="build"
NATIVE_ARCH="$(uname -m)"
ARCHS="${ARCHS:-$NATIVE_ARCH}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run:  xcode-select --install   then try again."
  exit 1
fi

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Compiling ($ARCHS)"
BINS=()
for arch in $ARCHS; do
  if [ "$arch" = "$NATIVE_ARCH" ] && [ "$(echo $ARCHS | wc -w)" -eq 1 ]; then
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)"
  else
    swift build -c release --arch "$arch"
    BIN_PATH="$(swift build -c release --arch "$arch" --show-bin-path)"
  fi
  BINS+=("$BIN_PATH/$APP_NAME")
done

echo "==> Creating app bundle"
APP="$BUILD_DIR/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${#BINS[@]}" -gt 1 ]; then
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else
  cp "${BINS[0]}" "$APP/Contents/MacOS/$APP_NAME"
fi
sed "s/__VERSION__/$VERSION/g" Packaging/Info.plist > "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

echo "==> Making icon"
if swift Scripts/make-icon.swift "$BUILD_DIR/icon_1024.png" >/dev/null 2>&1; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$BUILD_DIR/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (icon step skipped — app will use the default icon)"
fi

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Building DMG"
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD_DIR/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo ""
echo "Done!  $(pwd)/$BUILD_DIR/$APP_NAME.dmg"
echo "Open it and drag Ledge into Applications."
