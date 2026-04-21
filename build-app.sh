#!/bin/bash
set -e

APP_NAME="PeekBar"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME (release)..."
swift build -c release

echo "Creating $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "Sources/PeekBar/Info.plist" "$CONTENTS/Info.plist"
cp "Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# Copy SPM-generated resource bundle (menu bar icon PNGs)
RES_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RES_BUNDLE" ]; then
    cp -R "$RES_BUNDLE" "$RESOURCES/"
fi

# Sign with persistent identity so TCC permissions survive rebuilds
SIGN_ID="PeekBar Self-Signed"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" "$APP_BUNDLE"
    echo "Signed with '$SIGN_ID'"
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "Warning: '$SIGN_ID' not found, using ad-hoc signature (permissions won't persist)"
fi

# Deploy to /Applications, cleaning up the local bundle and relaunching
INSTALL_PATH="/Applications/$APP_BUNDLE"
WAS_RUNNING=0
if pgrep -x "$APP_NAME" > /dev/null; then
    WAS_RUNNING=1
    echo "Stopping running $APP_NAME..."
    pkill -x "$APP_NAME" || true
    # Give it a moment to release file handles
    for i in 1 2 3 4 5; do
        pgrep -x "$APP_NAME" > /dev/null || break
        sleep 0.2
    done
fi

echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
rm -rf "$APP_BUNDLE"

if [ "$WAS_RUNNING" -eq 1 ]; then
    open "$INSTALL_PATH"
    echo "Relaunched $APP_NAME"
fi

echo "Done! Installed at $INSTALL_PATH"
