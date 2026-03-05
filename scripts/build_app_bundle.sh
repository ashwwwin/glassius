#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="GlassiusCam"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/$APP_NAME"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_NAME="AppIcon.icns"
ICON_SOURCE_PATH="$ROOT_DIR/logo.png"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -f "$ICON_SOURCE_PATH" ]]; then
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16     "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SOURCE_PATH" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/$ICON_NAME"
    rm -rf "$ICONSET_DIR"
else
    echo "Warning: icon source not found at '$ICON_SOURCE_PATH'; using default app icon."
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>GlassiusCam</string>
    <key>CFBundleDisplayName</key>
    <string>GlassiusCam</string>
    <key>CFBundleIdentifier</key>
    <string>local.glassius.cam</string>
    <key>CFBundleExecutable</key>
    <string>GlassiusCam</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>${ICON_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>GlassiusCam uses the camera so your friend can see you.</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>GlassiusCam uses your local network to find and connect to your friend's Mac.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_glasscamchat._tcp</string>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "Built app bundle: $APP_DIR"
echo "Signed with identity: $SIGN_IDENTITY"
if ! spctl --assess --type execute "$APP_DIR" >/dev/null 2>&1; then
    echo "Gatekeeper assessment: rejected (expected for ad-hoc signing on many systems)."
fi
echo "Launch with: open '$APP_DIR'"
