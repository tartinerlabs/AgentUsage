#!/bin/sh
set -eu

# Xcode Cloud's macOS test-host signing does not embed a development profile
# for restricted capabilities. Requesting them makes Runningboard refuse to
# spawn AgentUsageTests (error 5). Archive/Release keeps the full entitlements
# file; this hook only mutates the throwaway Cloud checkout.
if [ "${CI_PRODUCT_PLATFORM:-}" != "macOS" ]; then
  exit 0
fi

repo="${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
entitlements="$repo/AgentUsage/AgentUsage.entitlements"

if [ ! -f "$entitlements" ]; then
  echo "warning: missing $entitlements" >&2
  exit 0
fi

for key in \
  keychain-access-groups \
  com.apple.developer.icloud-container-identifiers \
  com.apple.developer.icloud-services
do
  /usr/libexec/PlistBuddy -c "Delete :$key" "$entitlements" 2>/dev/null || true
done
