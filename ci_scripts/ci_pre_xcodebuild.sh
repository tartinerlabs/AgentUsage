#!/bin/sh
set -eu

# Xcode Cloud's macOS test-host signing does not embed a development profile
# for restricted capabilities. Requesting them makes Runningboard refuse to
# spawn AgentUsageTests (error 5). Only mutate the throwaway checkout for the
# macOS Test action; Archive/Release must keep Keychain Sharing and iCloud.
if [ "${CI_PRODUCT_PLATFORM:-}" != "macOS" ]; then
  exit 0
fi
if [ "${CI_XCODEBUILD_ACTION:-}" != "build-for-testing" ]; then
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
