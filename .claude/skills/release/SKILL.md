---
name: release
description: Create a new release for ClaudeMeter. Bumps version in Config/Version.xcconfig, updates CHANGELOG.md, commits, tags, pushes, and creates a GitHub release with detailed notes. Use when releasing a new version.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Release Skill

Create a new release for ClaudeMeter following Apple versioning standards.

## Prerequisites

- Working tree must be clean (no uncommitted changes)
- Must be on the `main` branch

## Workflow

### Step 1: Validate State

1. Check git status - must be clean
2. Verify on `main` branch
3. Read current version from `Config/Version.xcconfig`

### Step 2: Determine New Version

Ask the user what type of release:
- **patch**: 0.1.0 → 0.1.1 (bug fixes)
- **minor**: 0.1.0 → 0.2.0 (new features)
- **major**: 0.1.0 → 1.0.0 (breaking changes)

Or accept a specific version if provided.

### Step 3: Update Version Files

**IMPORTANT**: All platforms (macOS, iOS, widgets, tests) must have the same version numbers.

1. Update `Config/Version.xcconfig` (source of truth):
   - Increment `MARKETING_VERSION` to new version
   - Increment `CURRENT_PROJECT_VERSION` by 1

2. Update `ClaudeMeter.xcodeproj/project.pbxproj` to sync ALL targets:
   - Replace all `MARKETING_VERSION = X.Y.Z;` with the new version
   - Replace all `CURRENT_PROJECT_VERSION = N;` with the new build number
   - This includes: ClaudeMeter (macOS), ClaudeMeter-iOS, ClaudeMeterWidgetsExtension, and all test targets
   - Use the Edit tool with `replace_all: true` to update all occurrences

### Step 4: Update CHANGELOG.md

1. Read current `CHANGELOG.md`
2. Ask user for release notes (what was added, fixed, changed)
3. Add new version section under `[Unreleased]`:
   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD

   ### Added
   - New features here

   ### Fixed
   - Bug fixes here

   ### Changed
   - Changes here
   ```
4. Update comparison links at bottom of file

### Step 5: Commit and Tag

```bash
git add Config/Version.xcconfig ClaudeMeter.xcodeproj/project.pbxproj CHANGELOG.md
git commit -m "Bump version to X.Y.Z"
git tag vX.Y.Z
```

### Step 6: Push and Create Release

```bash
git push origin main
git push origin vX.Y.Z
```

Create GitHub release with detailed notes:
```bash
gh release create vX.Y.Z --title "ClaudeMeter X.Y.Z" --notes-file - --prerelease <<'EOF'
## What's New

[Extract from CHANGELOG.md for this version]

See [CHANGELOG.md](https://github.com/tartinerlabs/ClaudeMeter/blob/main/CHANGELOG.md) for full details.
EOF
```

Use `--prerelease` flag for versions < 1.0.0.

### Step 7: Verify

1. Confirm GitHub Actions workflow started
2. Provide link to the release

## Version Format

- **MARKETING_VERSION**: X.Y.Z (semantic versioning)
- **CURRENT_PROJECT_VERSION**: Integer, always increments (never decreases)

## Example

```
Current: 0.1.0 (build 1)
User requests: minor release with "Added dark mode support"
Result: 0.2.0 (build 2)
```
