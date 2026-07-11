#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
release_scripts="$repo_root/.github/scripts/release"
root=$(mktemp -d "${TMPDIR:-/tmp}/appcast-generation-test.XXXXXX")
trap 'rm -rf "$root"' EXIT

tools_dir="$root/sparkle"
SPARKLE_VERSION=2.8.1 \
SPARKLE_SHA256=5cddb7695674ef7704268f38eccaee80e3accbf19e61c1689efff5b6116d85be \
SPARKLE_DIR="$tools_dir" \
  "$release_scripts/download-sparkle.sh" >/dev/null

key_material=$(swift - <<'SWIFT'
import CryptoKit
import Foundation

let privateKey = Curve25519.Signing.PrivateKey()
print(privateKey.rawRepresentation.base64EncodedString())
print(privateKey.publicKey.rawRepresentation.base64EncodedString())
SWIFT
)
private_key=$(printf '%s\n' "$key_material" | sed -n '1p')
public_key=$(printf '%s\n' "$key_material" | sed -n '2p')

app="$root/AgentUsage.app"
mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$app/Contents/MacOS/AgentUsage"
chmod +x "$app/Contents/MacOS/AgentUsage"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.tartinerlabs.AgentUsage</string>
<key>CFBundleName</key><string>AgentUsage</string>
<key>CFBundleVersion</key><string>79</string>
<key>CFBundleShortVersionString</key><string>0.26.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>SUPublicEDKey</key><string>$public_key</string>
</dict></plist>
PLIST

mkdir -p "$root/build"
/usr/bin/ditto -c -k --keepParent "$app" "$root/build/AgentUsage.zip"
printf '<h2>Test release</h2><ul><li>Regression fixture</li></ul>\n' > "$root/notes.html"

# The final item and channel intentionally close on the same line. The previous
# line-oriented merger copied </channel> into the item range and broke the feed.
cat > "$root/existing-appcast.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>AgentUsage Updates</title><item><title>Version 0.25.0</title><sparkle:version>78</sparkle:version><sparkle:shortVersionString>0.25.0</sparkle:shortVersionString><enclosure url="https://example.invalid/AgentUsage.zip" length="1" type="application/octet-stream" sparkle:edSignature="old" /></item></channel></rss>
XML

(
  cd "$root"
  APP_NAME=AgentUsage \
  VERSION=0.26.0 \
  BUILD=79 \
  TAG=v0.26.0 \
  REPO=tartinerlabs/AgentUsage \
  GH_TOKEN=test-token \
  SPARKLE_PRIVATE_KEY="$private_key" \
  NOTES_HTML="$root/notes.html" \
  RUNNER_TEMP="$root/runner" \
  ARCHIVE_PATH="$root/build/AgentUsage.zip" \
  APPCAST_SOURCE="$root/existing-appcast.xml" \
  APPCAST_OUTPUT="$root/appcast.xml" \
  SPARKLE_TOOLS_DIR="$tools_dir" \
    "$release_scripts/generate-appcast.sh" >/dev/null
)

xmllint --noout "$root/appcast.xml"
[[ "$(grep -c '<sparkle:version>79</sparkle:version>' "$root/appcast.xml")" -eq 1 ]]
[[ "$(grep -c '<sparkle:version>78</sparkle:version>' "$root/appcast.xml")" -eq 1 ]]

# Re-running repair for the same build must update in place, not duplicate it.
cp -f "$root/appcast.xml" "$root/first-pass-appcast.xml"
(
  cd "$root"
  APP_NAME=AgentUsage \
  VERSION=0.26.0 \
  BUILD=79 \
  TAG=v0.26.0 \
  REPO=tartinerlabs/AgentUsage \
  GH_TOKEN=test-token \
  SPARKLE_PRIVATE_KEY="$private_key" \
  NOTES_HTML="$root/notes.html" \
  RUNNER_TEMP="$root/runner-second-pass" \
  ARCHIVE_PATH="$root/build/AgentUsage.zip" \
  APPCAST_SOURCE="$root/first-pass-appcast.xml" \
  APPCAST_OUTPUT="$root/appcast.xml" \
  SPARKLE_TOOLS_DIR="$tools_dir" \
    "$release_scripts/generate-appcast.sh" >/dev/null
)
[[ "$(grep -c '<sparkle:version>79</sparkle:version>' "$root/appcast.xml")" -eq 1 ]]

cat > "$root/duplicate-appcast.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><sparkle:version>79</sparkle:version></item>
<item><sparkle:version>79</sparkle:version></item>
</channel></rss>
XML
if "$release_scripts/validate-appcast.py" "$root/duplicate-appcast.xml" \
  --version 0.26.0 --build 79 --url https://example.invalid/AgentUsage.zip >/dev/null 2>&1; then
  echo "FAIL: duplicate appcast builds were accepted" >&2
  exit 1
fi

echo "appcast generation regression test passed"
