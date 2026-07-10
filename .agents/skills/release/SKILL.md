---
name: release
description: Operate ClaudeMeter's manual signed release workflow. Use for dry runs, signed publication, bump selection, or Sparkle appcast repair.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Release Skill

ClaudeMeter releases are explicitly triggered through `.github/workflows/release.yml`. A normal push to `main` runs CI only and never publishes a release.

## Safety model

- `dry-run` is the default operation and has read-only GitHub permissions.
- `publish` and `repair-appcast` use the protected `release` environment.
- Publishing is blocked unless `SIGNED_RELEASES_ENABLED=true` and all Developer ID, notarization, and Sparkle secrets are present.
- Do not manually edit versions, create tags, push release commits, or run `gh release create`. The workflow owns those operations.
- Versions below `1.0.0` are published as GitHub prereleases.

## Before running anything

1. Ensure the working tree is clean and `main` is current.
2. Read `Config/Version.xcconfig` and the latest `v*` tag.
3. Check the release gate without exposing values:

```bash
gh variable list --env release
gh secret list --env release
```

If signed releases are not enabled, only run a dry run.

## Dry run

Use `auto` unless the user selected a specific semantic bump:

```bash
gh workflow run release.yml \
  -f operation=dry-run \
  -f bump=auto
```

The dry run computes or resumes the version, runs tests, simulates version and changelog changes, and builds an unsigned validation artifact. It cannot commit, tag, release, or update the appcast.

## Publish

Only run this after the release environment is fully configured:

```bash
gh workflow run release.yml \
  -f operation=publish \
  -f bump=auto
```

The workflow:

1. Validates the release gate and secrets before mutation.
2. Computes the next version or resumes a committed untagged version.
3. Runs tests and prepares version/changelog changes.
4. Developer ID-signs, notarizes, staples, packages, and Gatekeeper-validates the app.
5. Generates and verifies the accumulating feed with Sparkle `generate_appcast`.
6. Commits the version bump using a compare-and-swap on `main`.
7. Creates the tag and GitHub prerelease.
8. Publishes `appcast.xml` to `gh-pages` and dispatches the Pages deployment.

## Repair an appcast

Use this only when a signed GitHub release exists but its feed item is missing or stale:

```bash
gh workflow run release.yml \
  -f operation=repair-appcast \
  -f tag=vX.Y.Z
```

Repair downloads and validates the existing release archive, reads its version/build metadata, regenerates the feed idempotently, and deploys Pages. It does not create or modify a tag, release, version file, or changelog entry.

## Bump rules

- `auto`: minor by default.
- `patch`: increment the patch component.
- `minor`: increment the minor component.
- `major`: increment the major component.
- If `Config/Version.xcconfig` contains an untagged version newer than the latest tag, that version and build are resumed and the requested bump is ignored.
- `[major]` in a release-worthy commit escalates `auto` to major.
- `[patch]` on every release-worthy commit changes `auto` to patch.
- A head commit containing `[skip release]` skips computation.

## Verification

After dispatching:

```bash
gh run list --workflow release.yml --limit 5
gh run watch
```

For a successful publish, verify the GitHub release, its `ClaudeMeter.zip` asset, and the live feed at `https://tartinerlabs.github.io/ClaudeMeter/appcast.xml`.

See `RELEASING.md` for credential setup and beginner-oriented explanations.
