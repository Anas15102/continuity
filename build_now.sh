#!/bin/zsh
cd /Users/anas/Desktop/smart
xcodebuild \
  -project ContinuityMac/ContinuityMac.xcodeproj \
  -scheme ContinuityMac \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tee /tmp/continuity_build.log
echo "EXIT: $?"
