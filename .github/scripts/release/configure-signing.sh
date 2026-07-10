#!/bin/bash

set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
: "${DEVELOPER_ID_APPLICATION_P12_BASE64:?Developer ID certificate is required}"
: "${DEVELOPER_ID_APPLICATION_PASSWORD:?Developer ID certificate password is required}"
: "${APPLE_NOTARY_KEY_P8_BASE64:?App Store Connect API key is required}"

CERTIFICATE_PATH="$RUNNER_TEMP/developer-id-application.p12"
NOTARY_KEY_PATH="$RUNNER_TEMP/AuthKey_${APPLE_NOTARY_KEY_ID}.p8"
KEYCHAIN_PATH="$RUNNER_TEMP/release-signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

echo "::add-mask::$KEYCHAIN_PASSWORD"
printf '%s' "$DEVELOPER_ID_APPLICATION_P12_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
printf '%s' "$APPLE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$NOTARY_KEY_PATH"
chmod 600 "$CERTIFICATE_PATH" "$NOTARY_KEY_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -P "$DEVELOPER_ID_APPLICATION_PASSWORD" \
  -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "Developer ID Application"

{
  echo "RELEASE_KEYCHAIN_PATH=$KEYCHAIN_PATH"
  echo "RELEASE_KEYCHAIN_PASSWORD=$KEYCHAIN_PASSWORD"
  echo "NOTARY_KEY_PATH=$NOTARY_KEY_PATH"
  echo "RELEASE_CERTIFICATE_PATH=$CERTIFICATE_PATH"
} >> "$GITHUB_ENV"
