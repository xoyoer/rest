#!/bin/bash
set -e

APP_NAME="休息"
BUNDLE_NAME="$APP_NAME.app"
BUILD_DIR="build"
SOURCES=$(find Sources -name "*.swift")
SDK=$(xcrun --show-sdk-path)
TARGET="arm64-apple-macosx14.0"

echo "Building $APP_NAME..."

# Clean
rm -rf "$BUILD_DIR"

# Create .app bundle structure
mkdir -p "$BUILD_DIR/$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$BUILD_DIR/$BUNDLE_NAME/Contents/Resources"

# Compile
swiftc $SOURCES \
    -o "$BUILD_DIR/$BUNDLE_NAME/Contents/MacOS/idle" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -O

# Copy resources
cp Info.plist "$BUILD_DIR/$BUNDLE_NAME/Contents/"
if [ -d Sources/Resources ] && [ "$(ls -A Sources/Resources 2>/dev/null)" ]; then
    cp Sources/Resources/* "$BUILD_DIR/$BUNDLE_NAME/Contents/Resources/" 2>/dev/null || true
fi

# Sign with persistent self-signed certificate (keeps TCC permissions across rebuilds)
CERT="xoyoer-idle"
ENTITLEMENTS="idle.entitlements"
if security find-certificate -c "$CERT" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    codesign --force --deep --sign "$CERT" --entitlements "$ENTITLEMENTS" "$BUILD_DIR/$BUNDLE_NAME"
else
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$BUILD_DIR/$BUNDLE_NAME"
    echo "  ⚠ 证书 '$CERT' 未找到，使用 ad-hoc 签名"
fi

echo "✓ Build complete: $BUILD_DIR/$BUNDLE_NAME"
echo "  Run: open $BUILD_DIR/$BUNDLE_NAME"
