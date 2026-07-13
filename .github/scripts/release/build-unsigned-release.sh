#!/bin/bash

set -euo pipefail

: "${APP_NAME:=AgentUsage}"
: "${SCHEME:=AgentUsage}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

ARCHIVE_PATH="build/$APP_NAME.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
FINAL_ZIP="build/$APP_NAME.zip"
VERIFICATION_DIR="$RUNNER_TEMP/unsigned-archive-verification"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$FINAL_ZIP" "$VERIFICATION_DIR"
mkdir -p "$EXPORT_PATH" "$VERIFICATION_DIR"

xcodebuild -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO

archived_app="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[[ -d "$archived_app" ]] || { echo "::error::Archived app not found at $archived_app"; exit 1; }
/usr/bin/ditto "$archived_app" "$APP_PATH"

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -F "Signature=adhoc"

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$VERIFICATION_DIR"

verified_app="$VERIFICATION_DIR/$APP_NAME.app"
[[ -d "$verified_app" ]] || { echo "::error::Packaged app not found at $verified_app"; exit 1; }
codesign --verify --deep --strict --verbose=4 "$verified_app"
codesign -dv --verbose=4 "$verified_app" 2>&1 | grep -F "Signature=adhoc"

echo "Ad-hoc-signed archive created at $FINAL_ZIP"
