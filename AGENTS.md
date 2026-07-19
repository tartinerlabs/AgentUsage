# Agent Instructions

## Design System

`DESIGN.md` is the source of truth for AgentUsage's SwiftUI visual system. When
changing SwiftUI views, widgets, menu bar UI, or Live Activities, consult it and
preserve its color, typography, spacing, material, icon, and status-system
rules.

## Build Targets

`AgentUsage` is the single destination-aware app and test scheme for macOS,
iOS, and iPadOS. `AgentUsageWidgetsExtension` remains the separate iOS widget
and Live Activity extension.

## Release Workflow

Releases use the manually triggered `.github/workflows/release.yml`; a normal push to `main` runs CI only. The default `dry-run` operation has read-only permissions and builds a fully validated ad-hoc-signed archive. Publishing always uses the protected `release` environment and requires the Sparkle private key.

`publish` is the Developer ID path and requires `SIGNED_RELEASES_ENABLED=true` plus the Apple signing and notarization secrets; it signs with Developer ID, notarizes, and staples. `publish-unsigned` is the ad-hoc fallback: it requires `UNSIGNED_RELEASES_ENABLED=true`, creates an ad-hoc code signature, and does not use Apple notarization. Both paths test, compute or resume the version, prepare the changelog, generate and verify the accumulating feed with Sparkle's official `generate_appcast`, commit with compare-and-swap protection, create the tag/prerelease, publish `appcast.xml` to `gh-pages`, and dispatch `pages.yml`.

Do not manually edit versions, tag, or call `gh release create`. Use:

```bash
gh workflow run release.yml -f operation=dry-run -f bump=auto
gh workflow run release.yml -f operation=publish-unsigned -f bump=auto
gh workflow run release.yml -f operation=publish -f bump=auto
gh workflow run release.yml -f operation=repair-appcast -f tag=vX.Y.Z
```

Signed, notarized Developer ID releases (`publish`) are the primary distribution mode, gated on `SIGNED_RELEASES_ENABLED=true` plus the Apple signing and notarization secrets in the `release` environment; `publish-unsigned` remains an ad-hoc fallback. An untagged version committed in `Config/Version.xcconfig` is resumed regardless of the requested bump. See `RELEASING.md` and `.agents/skills/release/SKILL.md` for setup, Gatekeeper behaviour, and recovery.

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**

```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**

- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var
