#!/bin/bash

set -euo pipefail

OPERATION="${OPERATION:-publish}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

require_value() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "Required release secret is missing: $name"
}

case "$OPERATION" in
  publish)
    [[ "${SIGNED_RELEASES_ENABLED:-}" == "true" ]] || fail "Signed releases are paused. Set SIGNED_RELEASES_ENABLED=true in the release environment after Developer ID credentials are configured."
    require_value SPARKLE_PRIVATE_KEY
    require_value DEVELOPER_ID_APPLICATION_P12_BASE64
    require_value DEVELOPER_ID_APPLICATION_PASSWORD
    require_value APPLE_NOTARY_KEY_P8_BASE64
    require_value APPLE_NOTARY_KEY_ID
    require_value APPLE_NOTARY_ISSUER_ID
    require_value APPLE_TEAM_ID
    ;;
  publish-unsigned)
    [[ "${UNSIGNED_RELEASES_ENABLED:-}" == "true" ]] || fail "Unsigned releases are paused. Set UNSIGNED_RELEASES_ENABLED=true in the release environment after accepting the Gatekeeper trade-off."
    require_value SPARKLE_PRIVATE_KEY
    ;;
  repair-appcast)
    if [[ "${SIGNED_RELEASES_ENABLED:-}" != "true" && "${UNSIGNED_RELEASES_ENABLED:-}" != "true" ]]; then
      fail "Appcast repair is paused. Enable the release mode that matches the published archive."
    fi
    require_value SPARKLE_PRIVATE_KEY
    ;;
  *)
    fail "Unsupported gated release operation: $OPERATION"
    ;;
esac

echo "Release gate passed for $OPERATION."
