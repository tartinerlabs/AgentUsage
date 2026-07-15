---
name: release
description: Operate AgentUsage's manual release workflow. Use for dry runs, explicit unsigned or Developer ID publication, bump selection, or Sparkle appcast repair.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Release Skill

AgentUsage releases are explicitly triggered through `.github/workflows/release.yml`. A normal push to `main` runs CI only and never publishes a release.

## Safety model

- `dry-run` is the default operation and has read-only GitHub permissions.
- `publish`, `publish-unsigned`, and `repair-appcast` use the protected `release` environment.
- `publish-unsigned` requires `UNSIGNED_RELEASES_ENABLED=true` and the Sparkle private key. It creates an ad-hoc signature and is not accepted by Gatekeeper without user approval.
- `publish` requires `SIGNED_RELEASES_ENABLED=true` plus all Developer ID, notarization, and Sparkle secrets.
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

Only dispatch a publication mode whose corresponding gate is enabled.

## Dry run

Use `auto` unless the user selected a specific semantic bump:

```bash
gh workflow run release.yml \
  -f operation=dry-run \
  -f bump=auto
```

The dry run computes or resumes the version, runs tests, simulates version and changelog changes, then builds, ad-hoc signs, packages, extracts, and verifies the unsigned archive. It cannot commit, tag, release, or update the appcast.

## Publish unsigned

Use this ad-hoc fallback path only after the unsigned gate is enabled and the dry run passes (the signed `publish` path is preferred once Apple credentials are configured):

```bash
gh workflow run release.yml \
  -f operation=publish-unsigned \
  -f bump=auto
```

This path uses strict ad-hoc code-signature validation and Sparkle EdDSA signing, but it does not notarize or pass Gatekeeper. Installation instructions must use Apple's **Open Anyway** flow and must not disable Gatekeeper globally.

## Publish signed

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

Use this when an existing signed or ad-hoc-signed GitHub release has a missing or stale feed item:

```bash
gh workflow run release.yml \
  -f operation=repair-appcast \
  -f tag=vX.Y.Z
```

Repair detects the archive signature. Developer ID archives must pass Gatekeeper and stapler checks; ad-hoc archives require the unsigned gate and strict `codesign` validation. It then reads version/build metadata, regenerates the feed idempotently, and deploys Pages without changing the release or source.

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

For a successful publish, verify the GitHub release, its `AgentUsage.zip` asset, signature mode, and the live feed at `https://tartinerlabs.github.io/AgentUsage/appcast.xml`. Gatekeeper rejection is expected only for `publish-unsigned`.

See `RELEASING.md` for credential setup and beginner-oriented explanations.
