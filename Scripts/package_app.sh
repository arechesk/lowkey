#!/usr/bin/env bash
# Builds lowkey.app. Usage: Scripts/package_app.sh [debug|release]
# Follows the release kit contract (Scripts/release/README.md):
#   ARCHES          architectures, space separated (default: this Mac's)
#   APP_OUTPUT_DIR  where lowkey.app is written (default: build/)
#   SIGNING_MODE    adhoc, or developer-id with APP_IDENTITY (Hardened Runtime, timestamp)
# Signs ad hoc unless APP_IDENTITY names a Developer ID certificate and SIGNING_MODE is not adhoc.
set -euo pipefail
CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
OUTPUT_DIR=${APP_OUTPUT_DIR:-"$ROOT/build"}
APP="$OUTPUT_DIR/lowkey.app"
BUNDLE_ID=io.bobuk.lowkey
read -r -a ARCH_LIST <<<"${ARCHES:-$(uname -m)}"

if pgrep -f -x "$APP/Contents/MacOS/Lowkey" >/dev/null; then
  echo "ERROR: $APP is running; quit it before rebuilding." >&2
  exit 1
fi

# The native build system writes each architecture to .build/<arch>-apple-macosx/<conf>.
BINARIES=()
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH" --build-system native
  BINARIES+=("$(swift build -c "$CONF" --arch "$ARCH" --build-system native --show-bin-path)/Lowkey")
done
"$ROOT/Scripts/build_icon.sh" "$ROOT/.build/Icon.icns"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Lowkey"
for ARCH in "${ARCH_LIST[@]}"; do lipo "$APP/Contents/MacOS/Lowkey" -verify_arch "$ARCH"; done
# Release builds drop debug-map paths (local home and build paths) before signing.
if [[ "$CONF" == release ]]; then xcrun strip -S "$APP/Contents/MacOS/Lowkey"; fi
cp "$ROOT/.build/Icon.icns" "$APP/Contents/Resources/Icon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>lowkey</string>
    <key>CFBundleDisplayName</key><string>lowkey</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Lowkey</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>${BUNDLE_ID}.deeplink</string>
        <key>CFBundleURLSchemes</key><array><string>lowkey</string></array>
    </dict></array>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
    <key>NSCameraUsageDescription</key><string>A website you open in lowkey asks to use the camera.</string>
    <key>NSMicrophoneUsageDescription</key><string>A website you open in lowkey asks to use the microphone.</string>
</dict>
</plist>
PLIST

cat > "$ROOT/.build/Lowkey.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key><true/>
    <key>com.apple.security.device.audio-input</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
if [[ -n "${APP_IDENTITY:-}" && "${SIGNING_MODE:-}" != adhoc ]]; then
  codesign --force --timestamp --options runtime --entitlements "$ROOT/.build/Lowkey.entitlements" --sign "$APP_IDENTITY" "$APP"
else
  codesign --force --sign - --entitlements "$ROOT/.build/Lowkey.entitlements" "$APP"
fi
echo "Created $APP"
