#!/bin/bash

set -euo pipefail

: "${APP_NAME:=AgentUsage}"
: "${SCHEME:=AgentUsage}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
: "${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"
: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

ARCHIVE_PATH="build/$APP_NAME.xcarchive"
EXPORT_PATH="build/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
NOTARIZATION_ZIP="build/$APP_NAME-notarization.zip"
FINAL_ZIP="build/$APP_NAME.zip"
EXPORT_OPTIONS="$RUNNER_TEMP/ExportOptions.plist"
NOTARY_RESPONSE="$RUNNER_TEMP/notary-response.json"
NOTARY_LOG="$RUNNER_TEMP/notary-log.json"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$NOTARIZATION_ZIP" "$FINAL_ZIP"
mkdir -p build

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>$APPLE_TEAM_ID</string>
</dict>
</plist>
PLIST

xcodebuild -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  "CODE_SIGN_IDENTITY[sdk=macosx*]=Developer ID Application" \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

[[ -d "$APP_PATH" ]] || { echo "::error::Exported app not found at $APP_PATH"; exit 1; }
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -F "Authority=Developer ID Application"

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$NOTARIZATION_ZIP"

set +e
xcrun notarytool submit "$NOTARIZATION_ZIP" \
  --key "$NOTARY_KEY_PATH" \
  --key-id "$APPLE_NOTARY_KEY_ID" \
  --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait \
  --output-format json > "$NOTARY_RESPONSE"
notary_status=$?
set -e

cat "$NOTARY_RESPONSE"
submission_id=$(jq -r '.id // empty' "$NOTARY_RESPONSE")
if [[ -n "$submission_id" ]]; then
  xcrun notarytool log "$submission_id" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID" \
    "$NOTARY_LOG" || true
  [[ ! -f "$NOTARY_LOG" ]] || cat "$NOTARY_LOG"
fi

[[ $notary_status -eq 0 ]] || { echo "::error::notarytool submission failed"; exit "$notary_status"; }
[[ "$(jq -r '.status // empty' "$NOTARY_RESPONSE")" == "Accepted" ]] || { echo "::error::Apple did not accept the notarization submission"; exit 1; }

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

verification_dir="$RUNNER_TEMP/final-archive-verification"
rm -rf "$verification_dir"
mkdir -p "$verification_dir"
/usr/bin/ditto -x -k "$FINAL_ZIP" "$verification_dir"
codesign --verify --deep --strict --verbose=4 "$verification_dir/$APP_NAME.app"
spctl --assess --type execute --verbose=4 "$verification_dir/$APP_NAME.app"

echo "Signed and notarized archive created at $FINAL_ZIP"
