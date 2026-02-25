#!/usr/bin/env bash
set -euo pipefail

# Configuration
DEVELOPER_ID="Developer ID Application: Whatever Co. (G5G54TCH8W)"
TEAM_ID="G5G54TCH8W"
KEYCHAIN_PROFILE="notarytool-profile"

APP_PATH="$1"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: App not found at $APP_PATH"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH" .app)
WORK_DIR=$(dirname "$APP_PATH")
ZIP_PATH="${WORK_DIR}/${APP_NAME}.zip"

echo "=== Signing $APP_NAME.app ==="

# Sign all nested bundles and binaries from inside out
# 1. Sign all Mach-O binaries inside Frameworks/ (deepest first)
find "$APP_PATH/Contents/Frameworks" -type f -perm +111 | sort -r | while read -r binary; do
  if file "$binary" | grep -q "Mach-O"; then
    echo "Signing $(echo "$binary" | sed "s|$APP_PATH/||")..."
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$binary"
  fi
done

# 2. Sign nested .app bundles inside Frameworks/
find "$APP_PATH/Contents/Frameworks" -name "*.app" -type d | while read -r nested_app; do
  echo "Signing bundle $(basename "$nested_app")..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$nested_app"
done

# 3. Sign XPC services inside Frameworks/
find "$APP_PATH/Contents/Frameworks" -name "*.xpc" -type d | while read -r xpc; do
  echo "Signing XPC $(basename "$xpc")..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$xpc"
done

# 4. Sign framework bundles
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d -maxdepth 1 | while read -r fw; do
  echo "Signing framework $(basename "$fw")..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$fw"
done

# 5. Sign dylibs
find "$APP_PATH" -name "*.dylib" -type f | while read -r dylib; do
  echo "Signing $(basename "$dylib")..."
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$dylib"
done

# 6. Sign all executables in Contents/MacOS/ (except the main app binary)
MACOS_DIR="$APP_PATH/Contents/MacOS"
MAIN_BINARY=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleExecutable 2>/dev/null || basename "$APP_PATH" .app)
for exe in "$MACOS_DIR"/*; do
  if [[ -f "$exe" && -x "$exe" && "$(basename "$exe")" != "$MAIN_BINARY" ]]; then
    echo "Signing $(basename "$exe")..."
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$exe"
  fi
done

# 7. Sign the main app bundle
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH"

# Verify signature
codesign --verify --verbose "$APP_PATH"
echo "Signature verified."

echo "=== Creating ZIP for notarization ==="
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "=== Submitting for notarization ==="
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "=== Stapling notarization ticket ==="
xcrun stapler staple "$APP_PATH"

# Verify stapled ticket
xcrun stapler validate "$APP_PATH"

# Clean up
rm -f "$ZIP_PATH"

echo "=== Notarization complete ==="
echo "$APP_PATH"
