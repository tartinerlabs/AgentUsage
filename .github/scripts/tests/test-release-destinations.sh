#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_literal() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file is missing: $expected"
}

require_count() {
  local file="$1"
  local expected="$2"
  local count="$3"
  local actual
  actual=$(grep -Fc -- "$expected" "$file" || true)
  [[ "$actual" -eq "$count" ]] || fail "$file contains '$expected' $actual times; expected $count"
}

require_literal \
  "$repo_root/.github/scripts/release/build-unsigned-release.sh" \
  '-destination "generic/platform=macOS"'
require_literal \
  "$repo_root/.github/scripts/release/build-signed-release.sh" \
  '-destination "generic/platform=macOS"'
require_count \
  "$repo_root/.github/workflows/release.yml" \
  "-destination 'platform=macOS'" \
  2
require_count \
  "$repo_root/.github/workflows/ci.yml" \
  "-destination 'platform=macOS'" \
  2

echo "release destination tests passed"
