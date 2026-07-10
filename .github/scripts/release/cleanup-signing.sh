#!/bin/bash

set -u

keychain_path="${RELEASE_KEYCHAIN_PATH:-${RUNNER_TEMP:-}/release-signing.keychain-db}"
certificate_path="${RELEASE_CERTIFICATE_PATH:-${RUNNER_TEMP:-}/developer-id-application.p12}"

if [[ -n "$keychain_path" ]]; then
  security delete-keychain "$keychain_path" 2>/dev/null || true
fi

rm -f "$certificate_path"
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  rm -f "$NOTARY_KEY_PATH"
elif [[ -n "${RUNNER_TEMP:-}" ]]; then
  rm -f "$RUNNER_TEMP"/AuthKey_*.p8
fi
