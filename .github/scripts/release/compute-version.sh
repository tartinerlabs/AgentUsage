#!/bin/bash

set -euo pipefail

BUMP_INPUT="${BUMP_INPUT:-auto}"
VERSION_FILE="${VERSION_FILE:-Config/Version.xcconfig}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

fail() {
  echo "::error::$*" >&2
  exit 1
}

version_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { value=$2; gsub(/[[:space:]]/, "", value); print value; exit }' "$VERSION_FILE"
}

validate_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Invalid semantic version: $1"
}

release_exists() {
  local version="$1"
  local owner name query response

  [[ -n "${GH_TOKEN:-}" && -n "${REPO:-}" ]] || return 1
  [[ "$REPO" == */* ]] || fail "Invalid GitHub repository name: $REPO"
  owner="${REPO%%/*}"
  name="${REPO#*/}"
  # GraphQL variables intentionally use literal $ syntax.
  # shellcheck disable=SC2016
  query='query($owner: String!, $name: String!, $tag: String!) {
    repository(owner: $owner, name: $name) { release(tagName: $tag) { id } }
  }'

  if ! response=$(gh api graphql \
    -f query="$query" \
    -F owner="$owner" \
    -F name="$name" \
    -F tag="v$version" \
    --jq '.data.repository.release != null'); then
    fail "Unable to check whether GitHub release v$version already exists"
  fi
  [[ "$response" == "true" ]]
}

version_gt() {
  local left_major left_minor left_patch right_major right_minor right_patch
  IFS=. read -r left_major left_minor left_patch <<< "$1"
  IFS=. read -r right_major right_minor right_patch <<< "$2"
  (( left_major > right_major )) ||
    (( left_major == right_major && left_minor > right_minor )) ||
    (( left_major == right_major && left_minor == right_minor && left_patch > right_patch ))
}

write_output() {
  printf '%s\n' "$1" >> "$OUTPUT_FILE"
}

case "$BUMP_INPUT" in
  auto|patch|minor|major) ;;
  *) fail "Unsupported bump type: $BUMP_INPUT" ;;
esac

LAST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null) || fail "No vX.Y.Z release tag exists"
LAST_VERSION="${LAST_TAG#v}"
validate_version "$LAST_VERSION"

CURRENT_MARKETING=$(version_value MARKETING_VERSION)
CURRENT_BUILD=$(version_value CURRENT_PROJECT_VERSION)
validate_version "$CURRENT_MARKETING"
[[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]] || fail "Invalid CURRENT_PROJECT_VERSION: $CURRENT_BUILD"

if git log -1 --format='%B' | grep -qF '[skip release]'; then
  echo "Head commit requests [skip release]; skipping."
  write_output "skip=true"
  exit 0
fi

RANGE="$LAST_TAG..HEAD"
SUBJECTS=$(git log "$RANGE" --no-merges --format='%s' \
  | grep -vE '^(Update appcast for v|Bump version to )' \
  | grep -vF '[skip release]' || true)
NOTES=$(printf '%s\n' "$SUBJECTS" \
  | sed -E 's/ *\[(minor|major|patch)\]//g' \
  | sed '/^[[:space:]]*$/d' \
  | sed 's/^/- /')

if [[ -z "$NOTES" ]]; then
  echo "No release-worthy commits since $LAST_TAG; skipping."
  write_output "skip=true"
  exit 0
fi

RESUME=false
BUMP="$BUMP_INPUT"

if version_gt "$LAST_VERSION" "$CURRENT_MARKETING"; then
  fail "$VERSION_FILE is behind the latest tag ($CURRENT_MARKETING < $LAST_VERSION)"
fi

if version_gt "$CURRENT_MARKETING" "$LAST_VERSION"; then
  if git rev-parse -q --verify "refs/tags/v$CURRENT_MARKETING" >/dev/null; then
    fail "Configured version $CURRENT_MARKETING already has a tag"
  fi
  if release_exists "$CURRENT_MARKETING"; then
    fail "Configured version $CURRENT_MARKETING already has a GitHub release"
  fi

  VERSION="$CURRENT_MARKETING"
  BUILD="$CURRENT_BUILD"
  RESUME=true
  BUMP=resume
  echo "Resuming untagged version $VERSION (build $BUILD); ignoring requested bump '$BUMP_INPUT'."
else
  if [[ "$BUMP" == "auto" ]]; then
    BODY=$(git log "$RANGE" --no-merges --format='%b')
    if printf '%s\n%s' "$SUBJECTS" "$BODY" | grep -qiF '[major]'; then
      BUMP='major'
    elif [[ -n "$SUBJECTS" ]] && ! printf '%s\n' "$SUBJECTS" | grep -qivF '[patch]'; then
      BUMP='patch'
    else
      BUMP='minor'
    fi
  fi

  IFS=. read -r major minor patch <<< "$LAST_VERSION"
  case "$BUMP" in
    major) VERSION="$((major + 1)).0.0" ;;
    minor) VERSION="$major.$((minor + 1)).0" ;;
    patch) VERSION="$major.$minor.$((patch + 1))" ;;
    *) fail "Unable to compute version for bump: $BUMP" ;;
  esac
  BUILD=$((CURRENT_BUILD + 1))
fi

if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  fail "Tag v$VERSION already exists"
fi

{
  echo "skip=false"
  echo "resume=$RESUME"
  echo "version=$VERSION"
  echo "tag=v$VERSION"
  echo "build_number=$BUILD"
  echo "last_tag=$LAST_TAG"
  echo "bump=$BUMP"
  echo "notes<<NOTES_EOF"
  echo "$NOTES"
  echo "NOTES_EOF"
} >> "$OUTPUT_FILE"

echo "Release candidate: $VERSION (build $BUILD, $BUMP from $LAST_TAG)"
echo "$NOTES"
