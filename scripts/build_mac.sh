#!/bin/zsh
# build_mac.sh — Build the macOS Continuity app via xcodebuild

set -e

PROJECT="ContinuityMac/ContinuityMac.xcodeproj"
SCHEME="ContinuityMac"
CONFIGURATION="Debug"
DERIVED_DATA="build/DerivedData"

echo "================================================"
echo "  Building ContinuityMac..."
echo "================================================"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tee build/mac_build.log

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/ContinuityMac.app"
  echo ""
  echo "✓ Build succeeded!"
  echo "  App: $APP_PATH"
  echo ""
  echo "  To run: open \"$APP_PATH\""
else
  echo ""
  echo "✗ Build failed. Check build/mac_build.log for details."
  exit 1
fi
