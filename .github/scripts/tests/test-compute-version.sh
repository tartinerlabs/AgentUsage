#!/bin/bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
compute_script="$repo_root/.github/scripts/release/compute-version.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

new_repo() {
  local directory="$1"
  local version="$2"
  local build="$3"
  mkdir -p "$directory/Config"
  git -C "$directory" init -q
  git -C "$directory" config user.name "Release Test"
  git -C "$directory" config user.email "release-test@example.com"
  printf 'MARKETING_VERSION = %s\nCURRENT_PROJECT_VERSION = %s\n' "$version" "$build" > "$directory/Config/Version.xcconfig"
  git -C "$directory" add Config/Version.xcconfig
  git -C "$directory" commit -qm "Initial release"
  git -C "$directory" tag "v$version"
}

add_commit() {
  local directory="$1"
  local subject="$2"
  local body="${3:-}"
  printf '%s\n' "$subject" >> "$directory/changes.txt"
  git -C "$directory" add changes.txt
  if [[ -n "$body" ]]; then
    git -C "$directory" commit -qm "$subject" -m "$body"
  else
    git -C "$directory" commit -qm "$subject"
  fi
}

output_value() {
  local output="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$output"
}

run_compute() {
  local directory="$1"
  local bump="$2"
  local output="$directory/output.txt"
  (
    cd "$directory"
    BUMP_INPUT="$bump" GITHUB_OUTPUT="$output" "$compute_script" >/dev/null
  )
  echo "$output"
}

root=$(mktemp -d "${TMPDIR:-/tmp}/compute-version-tests.XXXXXX")
trap 'rm -rf "$root"' EXIT

minor_repo="$root/minor"
new_repo "$minor_repo" 1.2.3 10
add_commit "$minor_repo" "Add dashboard"
minor_output=$(run_compute "$minor_repo" auto)
[[ "$(output_value "$minor_output" version)" == "1.3.0" ]] || fail "auto should default to minor"
[[ "$(output_value "$minor_output" build_number)" == "11" ]] || fail "minor should increment build"

patch_repo="$root/patch"
new_repo "$patch_repo" 1.2.3 10
add_commit "$patch_repo" "Fix updater [patch]"
patch_output=$(run_compute "$patch_repo" auto)
[[ "$(output_value "$patch_output" version)" == "1.2.4" ]] || fail "all-patch commits should produce patch"

major_repo="$root/major"
new_repo "$major_repo" 1.2.3 10
add_commit "$major_repo" "Change provider contract" "Migration required [major]"
major_output=$(run_compute "$major_repo" auto)
[[ "$(output_value "$major_output" version)" == "2.0.0" ]] || fail "major marker should win"

explicit_repo="$root/explicit"
new_repo "$explicit_repo" 1.2.3 10
add_commit "$explicit_repo" "Fix updater"
explicit_output=$(run_compute "$explicit_repo" patch)
[[ "$(output_value "$explicit_output" version)" == "1.2.4" ]] || fail "explicit patch should be honored"

resume_repo="$root/resume"
new_repo "$resume_repo" 1.2.3 10
add_commit "$resume_repo" "Add provider"
sed -i '' 's/MARKETING_VERSION = 1.2.3/MARKETING_VERSION = 1.3.0/' "$resume_repo/Config/Version.xcconfig"
sed -i '' 's/CURRENT_PROJECT_VERSION = 10/CURRENT_PROJECT_VERSION = 11/' "$resume_repo/Config/Version.xcconfig"
git -C "$resume_repo" add Config/Version.xcconfig
git -C "$resume_repo" commit -qm "Bump version to 1.3.0"
resume_output=$(run_compute "$resume_repo" patch)
[[ "$(output_value "$resume_output" version)" == "1.3.0" ]] || fail "untagged configured version should resume"
[[ "$(output_value "$resume_output" build_number)" == "11" ]] || fail "resume should preserve build"
[[ "$(output_value "$resume_output" resume)" == "true" ]] || fail "resume output should be true"

mock_bin="$root/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gh" <<'SH'
#!/bin/sh
echo true
SH
chmod +x "$mock_bin/gh"
if (
  cd "$resume_repo"
  PATH="$mock_bin:$PATH" GH_TOKEN=test REPO=owner/repo \
    BUMP_INPUT=patch GITHUB_OUTPUT="$resume_repo/release-exists-output.txt" \
    "$compute_script" >/dev/null 2>&1
); then
  fail "resume should reject a configured version that already has a GitHub release"
fi

skip_repo="$root/skip"
new_repo "$skip_repo" 1.2.3 10
add_commit "$skip_repo" "Update internal docs [skip release]"
skip_output=$(run_compute "$skip_repo" auto)
[[ "$(output_value "$skip_output" skip)" == "true" ]] || fail "skip marker should skip"

echo "compute-version tests passed"
