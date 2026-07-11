#!/bin/bash

set -euo pipefail

: "${APP_NAME:=AgentUsage}"
: "${VERSION:?VERSION is required}"
: "${BUILD:?BUILD is required}"
: "${TAG:?TAG is required}"
: "${REPO:?REPO is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
: "${NOTES_HTML:?NOTES_HTML is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

ARCHIVE_PATH="${ARCHIVE_PATH:-build/$APP_NAME.zip}"
APPCAST_OUTPUT="${APPCAST_OUTPUT:-appcast.xml}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
SPARKLE_SHA256="${SPARKLE_SHA256:-5cddb7695674ef7704268f38eccaee80e3accbf19e61c1689efff5b6116d85be}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-}"
APPCAST_SOURCE="${APPCAST_SOURCE:-}"

[[ -f "$ARCHIVE_PATH" ]] || { echo "::error::Release archive not found: $ARCHIVE_PATH"; exit 1; }
[[ -f "$NOTES_HTML" ]] || { echo "::error::HTML release notes not found: $NOTES_HTML"; exit 1; }

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
input_dir="$RUNNER_TEMP/appcast-input"
sparkle_dir="$RUNNER_TEMP/sparkle-$SPARKLE_VERSION"
rm -rf "$input_dir"
mkdir -p "$input_dir"
cp -f "$ARCHIVE_PATH" "$input_dir/$APP_NAME.zip"
cp -f "$NOTES_HTML" "$input_dir/$APP_NAME.html"

if [[ -n "$APPCAST_SOURCE" ]]; then
  cp -f "$APPCAST_SOURCE" "$input_dir/appcast.xml"
else
  gh api "repos/$REPO/contents/appcast.xml?ref=gh-pages" \
    -H "Accept: application/vnd.github.raw" > "$input_dir/appcast.xml"
fi
xmllint --noout "$input_dir/appcast.xml"

if [[ -n "$SPARKLE_TOOLS_DIR" ]]; then
  sparkle_dir="$SPARKLE_TOOLS_DIR"
else
  SPARKLE_VERSION="$SPARKLE_VERSION" \
  SPARKLE_SHA256="$SPARKLE_SHA256" \
  SPARKLE_DIR="$sparkle_dir" \
    "$script_dir/download-sparkle.sh"
fi

download_url="https://github.com/$REPO/releases/download/$TAG/$APP_NAME.zip"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_dir/bin/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --full-release-notes-url "https://github.com/$REPO/blob/main/CHANGELOG.md" \
  --link "https://github.com/$REPO/releases" \
  --maximum-versions 0 \
  --maximum-deltas 0 \
  --versions "$BUILD" \
  --embed-release-notes \
  -o "$input_dir/appcast.xml" \
  "$input_dir"

xmllint --noout "$input_dir/appcast.xml"
signature=$("$script_dir/validate-appcast.py" \
  "$input_dir/appcast.xml" \
  --version "$VERSION" \
  --build "$BUILD" \
  --url "$download_url")

printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_dir/bin/sign_update" \
  --verify \
  --ed-key-file - \
  "$input_dir/$APP_NAME.zip" \
  "$signature"

cp -f "$input_dir/appcast.xml" "$APPCAST_OUTPUT"
echo "Validated appcast for $TAG (build $BUILD) at $APPCAST_OUTPUT"
