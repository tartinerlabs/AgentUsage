#!/bin/bash

set -euo pipefail

: "${APP_NAME:=AgentUsage}"
: "${VERSION:?VERSION is required}"
: "${TAG:?TAG is required}"
: "${NOTES_FILE:?NOTES_FILE is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

archive_path="build/$APP_NAME.zip"
[[ -f "$archive_path" ]] || { echo "::error::Release archive not found: $archive_path"; exit 1; }
[[ -f "$NOTES_FILE" ]] || { echo "::error::Release notes not found: $NOTES_FILE"; exit 1; }

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "::error::Release $TAG already exists; use repair-appcast for feed recovery"
  exit 1
fi

flags=()
if [[ "$VERSION" == 0.* ]]; then
  flags+=(--prerelease)
fi

gh release create "$TAG" "$archive_path#$APP_NAME.zip" \
  --target "$(git rev-parse HEAD)" \
  --title "$APP_NAME $VERSION" \
  --notes-file "$NOTES_FILE" \
  "${flags[@]}"
