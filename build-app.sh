#!/bin/bash
set -e

APP_NAME="PeekBar"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

echo "Building $APP_NAME (release)..."
swift build -c release

echo "Creating $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "Sources/PeekBar/Info.plist" "$CONTENTS/Info.plist"

# Sign with persistent identity so TCC permissions survive rebuilds
SIGN_ID="PeekBar Self-Signed"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" "$APP_BUNDLE"
    echo "Signed with '$SIGN_ID'"
else
    codesign --force --sign - "$APP_BUNDLE"
    echo "Warning: '$SIGN_ID' not found, using ad-hoc signature (permissions won't persist)"
fi

echo "Done! Created $APP_BUNDLE"
echo ""
echo "To run:  open $APP_BUNDLE"
echo "To install:  cp -r $APP_BUNDLE /Applications/"
