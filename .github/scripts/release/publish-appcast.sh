#!/bin/bash

set -euo pipefail

: "${REPO:?REPO is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${TAG:?TAG is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

APPCAST_PATH="${APPCAST_PATH:-appcast.xml}"
[[ -f "$APPCAST_PATH" ]] || { echo "::error::Appcast not found: $APPCAST_PATH"; exit 1; }
xmllint --noout "$APPCAST_PATH"

current_appcast="$RUNNER_TEMP/current-appcast.xml"
if gh api "repos/$REPO/contents/appcast.xml?ref=gh-pages" \
  -H "Accept: application/vnd.github.raw" > "$current_appcast" 2>/dev/null \
  && cmp -s "$current_appcast" "$APPCAST_PATH"; then
  echo "gh-pages already contains this appcast; nothing to publish."
  exit 0
fi

base64 < "$APPCAST_PATH" | tr -d '\n' > "$RUNNER_TEMP/appcast.b64"
jq -n --arg path appcast.xml --rawfile contents "$RUNNER_TEMP/appcast.b64" \
  '[{path: $path, contents: $contents}]' > "$RUNNER_TEMP/appcast-additions.json"

# GraphQL variables intentionally use $ syntax.
# shellcheck disable=SC2016
query='mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) { commit { oid } }
}'

head_oid=$(gh api "repos/$REPO/branches/gh-pages" --jq '.commit.sha')
for attempt in 1 2 3; do
  jq -n --arg query "$query" --arg repo "$REPO" \
    --arg message "Update appcast for $TAG" --arg oid "$head_oid" \
    --slurpfile additions "$RUNNER_TEMP/appcast-additions.json" \
    '{query: $query, variables: {input: {
       branch: {repositoryNameWithOwner: $repo, branchName: "gh-pages"},
       message: {headline: $message},
       expectedHeadOid: $oid,
       fileChanges: {additions: $additions[0]}}}}' > "$RUNNER_TEMP/appcast-payload.json"

  if gh api graphql --input "$RUNNER_TEMP/appcast-payload.json" > "$RUNNER_TEMP/appcast-response.json"; then
    jq -e '.data.createCommitOnBranch.commit.oid' "$RUNNER_TEMP/appcast-response.json"
    echo "Published appcast for $TAG to gh-pages."
    exit 0
  fi

  [[ $attempt -lt 3 ]] || break
  head_oid=$(gh api "repos/$REPO/branches/gh-pages" --jq '.commit.sha')
done

echo "::error::Failed to publish appcast after 3 attempts"
exit 1
