#!/bin/zsh
# build_android.sh — Build the Android companion APK

set -e

ANDROID_DIR="ContinuityAndroid"
APK_OUTPUT="$ANDROID_DIR/app/build/outputs/apk/debug/app-debug.apk"

echo "================================================"
echo "  Building ContinuityAndroid APK..."
echo "================================================"

cd "$ANDROID_DIR"

# Use gradlew if available, otherwise fall back to system gradle
if [ -f "./gradlew" ]; then
  chmod +x ./gradlew
  ./gradlew assembleDebug 2>&1 | tee ../build/android_build.log
else
  gradle assembleDebug 2>&1 | tee ../build/android_build.log
fi

cd ..

if [ -f "$APK_OUTPUT" ]; then
  echo ""
  echo "✓ APK built successfully!"
  echo "  APK: $APK_OUTPUT"
  echo ""
  echo "  To install on connected device:"
  echo "  adb install -r \"$APK_OUTPUT\""
else
  echo ""
  echo "✗ APK build failed. Check build/android_build.log"
  exit 1
fi
