#!/bin/bash
# Xcode build phase of the iOS and tvOS apps: embeds build/ApplePython/$PLATFORM_NAME, made by
# Scripts/build-apple-python.sh, and signs its frameworks before Xcode signs the app. A build without it
# still works: ApplePython.c then reports Python as missing and the app offers no Python sources.
set -euo pipefail
SOURCE="$SRCROOT/build/ApplePython/$PLATFORM_NAME"
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
if [ ! -d "$SOURCE" ]; then
  case "$PLATFORM_NAME" in
    iphoneos) target=ios ;; iphonesimulator) target=ios-simulator ;; appletvos) target=tvos ;; *) target=tvos-simulator ;;
  esac
  echo "warning: This build has no Python runtime, so Python sources won't run. Run Scripts/build-apple-python.sh $target first."
  rm -rf "$APP/python" "$APP/PythonHost" "$APP/Frameworks/Python.framework"
  exit 0
fi
rsync -a --delete "$SOURCE/python/" "$APP/python/"
rsync -a --delete "$SOURCE/PythonHost/" "$APP/PythonHost/"
mkdir -p "$APP/Frameworks"
for framework in "$SOURCE/Frameworks/"*.framework; do
  rsync -a --delete "$framework/" "$APP/Frameworks/$(basename "$framework")/"
done
if [ "${CODE_SIGNING_ALLOWED:-YES}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  for framework in "$SOURCE/Frameworks/"*.framework; do
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" ${OTHER_CODE_SIGN_FLAGS:-} -o runtime --timestamp=none \
      --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$APP/Frameworks/$(basename "$framework")"
  done
fi
