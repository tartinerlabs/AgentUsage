---
name: release
description: Operate ClaudeMeter's automated release pipeline. Releases happen automatically on push to main via .github/workflows/auto-release.yml. Use when the user asks how releases work, wants a minor/major bump, wants to skip a release, needs a manual release, or needs to recover from a failed release run.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Release Skill

Releases are **fully automated**. Every code push to `main` triggers `.github/workflows/auto-release.yml`, which:

1. Computes the next version from the latest `v*` tag (minor by default)
2. Generates release notes from commit subjects since that tag
3. Runs the macOS test suite — any failure aborts before anything is pushed
4. Bumps `Config/Version.xcconfig`, `project.pbxproj`, and `CHANGELOG.md`, commits "Bump version to X.Y.Z"
5. Builds, ad-hoc signs, and zips the app
6. Creates the GitHub release with the zip attached (tag is created here, only after a successful build; `--prerelease` while < 1.0.0)
7. EdDSA-signs the zip, prepends this release's item to the existing feed (fetched from `gh-pages`) so the appcast **accumulates full version history**, and publishes the updated `appcast.xml` to the `gh-pages` branch (the final, user-visible release act). The Sparkle feed is served from GitHub Pages off `gh-pages`; `appcast.xml` lives only there, not on main. `.github/workflows/pages.yml` then deploys it via `workflow_run`.

There is no manual version bumping, tagging, or `gh release create` anymore.

The bespoke release logic lives in local composite actions under `.github/actions/` (`compute-version`, `bump-version`, `commit-push`, `generate-appcast`), consumed by `auto-release.yml`.

## Controlling the automation

### Bump type

- Default: **minor** (0.14.2 → 0.15.0) — a release is assumed to add something user-facing, since plain commit subjects carry no type to infer from
- Include the literal token `[patch]` on **every** release-worthy commit since the last tag to downgrade to a patch (0.14.2 → 0.14.3) — use for pure bug-fix releases
  - Example: `Fix menu bar badge alignment [patch]`
- Include the literal token `[major]` anywhere in a commit subject or body to escalate to a major (breaking) bump; it wins over everything else. Markers are stripped from release notes.
  - Example: `Drop legacy usage endpoint [major]`
- `[minor]` is still accepted but is a no-op alias of the default

### Skipping a release

A push does NOT release when any of these hold:

- It only touches non-code paths: `**/*.md`, `Config/Version.xcconfig`, `.beads/**`, `.claude/**`, `.github/**`, `.gitignore`
- The head commit message contains `[skip release]`
- All commits since the last tag filter out as noise (`Update appcast for v…`, `Bump version to …`, `Update beads…`, `[skip release]` commits)

### Manual trigger / dry run

```bash
# Force a specific bump type
gh workflow run auto-release.yml -f bump=minor

# Dry run: computes version + notes, runs tests, prints the would-be
# CHANGELOG/xcconfig diff — pushes and releases nothing
gh workflow run auto-release.yml -f dry_run=true

# Watch it
gh run watch
```

### Better release notes

Auto-notes are a flat bullet list of commit subjects. If richer notes are wanted, write good commit subjects — they ARE the release notes. The `## [Unreleased]` CHANGELOG section is still honored: anything placed there manually stays above the auto-inserted version section.

## Expected bot commits

Each release produces two `github-actions[bot]` commits on main: `Bump version to X.Y.Z` and `Update appcast for vX.Y.Z`. These never retrigger the workflow (GITHUB_TOKEN pushes don't fire workflows, and the touched paths are ignored anyway). They are created via the GraphQL `createCommitOnBranch` mutation rather than `git push`, so GitHub signs them and they show as **Verified**.

## Failure recovery

- **Tests fail**: nothing was pushed. Fix and push again.
- **"main moved during the release run"**: someone pushed while the release was in flight. Nothing was released; the workflow run queued for that push (or the next code push) releases everything together. Benign.
- **Build fails after the bump commit**: main has the bump commit but no tag/release. The next push (or re-running the failed run) detects xcconfig already at the computed version and resumes straight to build.
- **Appcast push fails** (rare): the release exists but the Sparkle feed is stale. Re-run the failed run (the generate-appcast step re-fetches the current `gh-pages` feed and re-prepends this release's item — it is idempotent, deduping by build number). If pushing `appcast.xml` to `gh-pages` by hand, keep it an accumulating feed — prepend the new item to the current feed rather than overwriting with a single item, then trigger `pages.yml` to redeploy. Or delete the release + tag and re-run.
- **Tag exists error**: a release already went out for that version; usually means a re-run after full success — nothing to do.

## Version format

- **MARKETING_VERSION**: X.Y.Z (semantic versioning) — cosmetic to Sparkle
- **CURRENT_PROJECT_VERSION**: integer build number, +1 per release, never decreases — this is what Sparkle compares for updates
