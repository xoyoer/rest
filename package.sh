#!/bin/bash
set -e

APP_NAME="休息"
BUILD_DIR="build"
BUNDLE_NAME="$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist 2>/dev/null || echo "1.0.0")
DMG_NAME="Rest-${VERSION}.dmg"

# Build first if needed
if [ ! -d "$BUILD_DIR/$BUNDLE_NAME" ]; then
    echo "App not found, building first..."
    bash build.sh
fi

echo "Packaging $APP_NAME v$VERSION..."

# Clean old DMG
rm -f "$BUILD_DIR/$DMG_NAME"
rm -rf "$BUILD_DIR/dmg-staging"

# Create staging directory with app and Applications symlink
mkdir -p "$BUILD_DIR/dmg-staging"
cp -R "$BUILD_DIR/$BUNDLE_NAME" "$BUILD_DIR/dmg-staging/"
cp 安装说明.txt "$BUILD_DIR/dmg-staging/"
ln -s /Applications "$BUILD_DIR/dmg-staging/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$BUILD_DIR/dmg-staging" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

# Clean staging
rm -rf "$BUILD_DIR/dmg-staging"

echo "✓ Package complete: $BUILD_DIR/$DMG_NAME"
