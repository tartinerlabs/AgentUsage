#!/bin/bash

set -euo pipefail

: "${TAG:?TAG is required}"
: "${APP_NAME:=ClaudeMeter}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

[[ "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || { echo "::error::Repair tag must be a semantic version in vX.Y.Z format"; exit 1; }
gh release view "$TAG" >/dev/null

repair_dir="build/appcast-repair"
extract_dir="$RUNNER_TEMP/appcast-repair-extracted"
rm -rf "$repair_dir" "$extract_dir"
mkdir -p "$repair_dir" "$extract_dir"
gh release download "$TAG" --pattern "$APP_NAME.zip" --dir "$repair_dir"

archive_path="$repair_dir/$APP_NAME.zip"
/usr/bin/ditto -x -k "$archive_path" "$extract_dir"
info_plist="$extract_dir/$APP_NAME.app/Contents/Info.plist"
[[ -f "$info_plist" ]] || { echo "::error::Release archive does not contain $APP_NAME.app"; exit 1; }
app_path="$extract_dir/$APP_NAME.app"
codesign --verify --deep --strict --verbose=4 "$app_path"

signature_details=$(codesign -dv --verbose=4 "$app_path" 2>&1)
if grep -Fq "Signature=adhoc" <<< "$signature_details"; then
  [[ "${UNSIGNED_RELEASES_ENABLED:-}" == "true" ]] || { echo "::error::Release archive is ad-hoc signed, but unsigned releases are disabled"; exit 1; }
  release_mode="unsigned"
  echo "Validated ad-hoc code signature for $TAG; Gatekeeper and notarization checks do not apply."
elif grep -Fq "Authority=Developer ID Application" <<< "$signature_details"; then
  [[ "${SIGNED_RELEASES_ENABLED:-}" == "true" ]] || { echo "::error::Release archive uses Developer ID, but signed releases are disabled"; exit 1; }
  release_mode="signed"
  spctl --assess --type execute --verbose=4 "$app_path"
  xcrun stapler validate "$app_path"
else
  echo "::error::Release archive has neither an ad-hoc nor Developer ID Application signature"
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
[[ "$TAG" == "v$version" ]] || { echo "::error::Release tag $TAG does not match archive version $version"; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "::error::Release archive has an invalid build number: $build"; exit 1; }

gh release view "$TAG" --json body --jq '.body' > "$RUNNER_TEMP/repair-release-body.txt"
{
  echo "version=$version"
  echo "build=$build"
  echo "release_mode=$release_mode"
  echo "archive_path=$archive_path"
  echo "notes_path=$RUNNER_TEMP/repair-release-body.txt"
} >> "$GITHUB_OUTPUT"
