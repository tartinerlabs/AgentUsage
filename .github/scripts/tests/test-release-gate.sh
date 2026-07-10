#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
gate="$repo_root/.github/scripts/release/check-release-gate.sh"

if OPERATION=publish "$gate" >/dev/null 2>&1; then
  echo "FAIL: publish passed while signed releases were disabled" >&2
  exit 1
fi

if OPERATION=publish-unsigned SPARKLE_PRIVATE_KEY=test "$gate" >/dev/null 2>&1; then
  echo "FAIL: unsigned publish passed while unsigned releases were disabled" >&2
  exit 1
fi

if UNSIGNED_RELEASES_ENABLED=true OPERATION=publish-unsigned "$gate" >/dev/null 2>&1; then
  echo "FAIL: unsigned publish passed without a Sparkle key" >&2
  exit 1
fi

UNSIGNED_RELEASES_ENABLED=true \
OPERATION=publish-unsigned \
SPARKLE_PRIVATE_KEY=test \
  "$gate" >/dev/null

if SIGNED_RELEASES_ENABLED=true OPERATION=publish SPARKLE_PRIVATE_KEY=test "$gate" >/dev/null 2>&1; then
  echo "FAIL: publish passed with missing Apple credentials" >&2
  exit 1
fi

if OPERATION=repair-appcast SPARKLE_PRIVATE_KEY=test "$gate" >/dev/null 2>&1; then
  echo "FAIL: repair passed while all release modes were disabled" >&2
  exit 1
fi

SIGNED_RELEASES_ENABLED=true \
OPERATION=repair-appcast \
SPARKLE_PRIVATE_KEY=test \
  "$gate" >/dev/null

UNSIGNED_RELEASES_ENABLED=true \
OPERATION=repair-appcast \
SPARKLE_PRIVATE_KEY=test \
  "$gate" >/dev/null

SIGNED_RELEASES_ENABLED=true \
OPERATION=publish \
SPARKLE_PRIVATE_KEY=test \
DEVELOPER_ID_APPLICATION_P12_BASE64=test \
DEVELOPER_ID_APPLICATION_PASSWORD=test \
APPLE_NOTARY_KEY_P8_BASE64=test \
APPLE_NOTARY_KEY_ID=test \
APPLE_NOTARY_ISSUER_ID=test \
APPLE_TEAM_ID=test \
  "$gate" >/dev/null

if SIGNED_RELEASES_ENABLED=true UNSIGNED_RELEASES_ENABLED=true OPERATION=unknown SPARKLE_PRIVATE_KEY=test \
  "$gate" >/dev/null 2>&1; then
  echo "FAIL: release gate accepted an unsupported operation" >&2
  exit 1
fi

repair="$repo_root/.github/scripts/release/prepare-appcast-repair.sh"
if TAG=v01.2.3 APP_NAME=ClaudeMeter GH_TOKEN=test RUNNER_TEMP="${TMPDIR:-/tmp}" GITHUB_OUTPUT=/dev/null \
  "$repair" >/dev/null 2>&1; then
  echo "FAIL: repair accepted a non-semver tag" >&2
  exit 1
fi

echo "release gate tests passed"
