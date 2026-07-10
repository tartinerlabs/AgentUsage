#!/bin/bash

set -euo pipefail

: "${SPARKLE_VERSION:=2.8.1}"
: "${SPARKLE_SHA256:?SPARKLE_SHA256 is required}"
: "${SPARKLE_DIR:?SPARKLE_DIR is required}"

archive_path="${SPARKLE_DIR}.tar.xz"
download_url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

rm -rf "$SPARKLE_DIR" "$archive_path"
mkdir -p "$SPARKLE_DIR"
curl --fail --location --proto '=https' --tlsv1.2 --output "$archive_path" "$download_url"
printf '%s  %s\n' "$SPARKLE_SHA256" "$archive_path" | shasum -a 256 -c -
tar -xf "$archive_path" -C "$SPARKLE_DIR"

[[ -x "$SPARKLE_DIR/bin/generate_appcast" ]] || { echo "::error::Sparkle generate_appcast was not found"; exit 1; }
[[ -x "$SPARKLE_DIR/bin/sign_update" ]] || { echo "::error::Sparkle sign_update was not found"; exit 1; }
