# Releasing AgentUsage

AgentUsage uses a manually triggered GitHub Actions workflow. “Manual” only
means a person chooses when a release starts; the workflow still handles the
version, tests, signing, notarization, packaging, Sparkle feed, tag, and GitHub
release.

AgentUsage publishes Developer ID-signed, notarized releases through the
`publish` operation, which Gatekeeper trusts on first launch. The ad-hoc-signed
`publish-unsigned` path remains available as a fallback, but Gatekeeper blocks it
until the user approves the app manually.

## The moving pieces

- **CI** builds and tests ordinary pushes and pull requests. It never publishes.
- **Developer ID signing** gives the app a stable identity that Gatekeeper can
  trust when it is downloaded outside the Mac App Store.
- **Ad-hoc signing** makes the bundle internally self-consistent without
  identifying the developer to Gatekeeper. Users must explicitly approve the
  first launch in System Settings.
- **Notarization** submits the signed app to Apple for automated security
  checks. The resulting ticket is stapled to the app before the final ZIP is
  created.
- **Sparkle** signs the ZIP with a separate EdDSA key and maintains
  `appcast.xml`, which tells installed copies that an update exists.
- **GitHub Pages** serves the appcast at
  `https://tartinerlabs.github.io/AgentUsage/appcast.xml`.

Developer ID and Sparkle signatures solve different problems. Sparkle's EdDSA
signature authenticates updates delivered to existing users. Developer ID and
notarization satisfy Gatekeeper for fresh downloads; the ad-hoc fallback still
carries the Sparkle signature but cannot satisfy Gatekeeper.

## Running a dry run

A dry run is safe before the Apple membership is ready:

```bash
gh workflow run release.yml \
  -f operation=dry-run \
  -f bump=auto
```

It calculates the version and notes, runs the macOS tests, simulates changes to
the version files and changelog, then builds, ad-hoc signs, packages, extracts,
and verifies the same archive shape used by unsigned publication. Its job token
is read-only, and it contains no publishing steps.

Use `patch`, `minor`, or `major` instead of `auto` to force a bump. An untagged
configured version in `Config/Version.xcconfig` is always resumed instead of
bumped again; once that version is tagged, `bump=auto` computes the next one.

## One-time unsigned-release setup

Unsigned publication is fail-closed even though it does not use Apple
credentials. The `release` environment must opt in explicitly, and the
repository-level `SPARKLE_PRIVATE_KEY` secret must remain configured:

```bash
gh variable set UNSIGNED_RELEASES_ENABLED --env release --body true
gh secret list --repo tartinerlabs/AgentUsage
```

Do not print, rotate, or duplicate the existing Sparkle private key merely to
enable this mode. Keep `SIGNED_RELEASES_ENABLED` unset until all Apple
credentials are available.

## Publishing an unsigned release

Always run the dry run first. After it succeeds:

```bash
gh workflow run release.yml \
  -f operation=publish-unsigned \
  -f bump=auto
```

The workflow validates the unsigned gate and Sparkle key, tests, prepares the
version and changelog, creates and verifies an ad-hoc-signed ZIP, signs the ZIP
with Sparkle EdDSA, commits the version, creates the tag and GitHub prerelease,
publishes the feed, and deploys Pages.

### Gatekeeper behaviour

An ad-hoc signature is not a Developer ID identity, and the archive is not
notarized. On first launch, macOS blocks the app as coming from an unidentified
developer. Users should attempt to open AgentUsage once, then open **System
Settings → Privacy & Security**, click **Open Anyway** for AgentUsage, and
confirm **Open**. Do not instruct users to disable Gatekeeper globally. See
[Apple's current guidance](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

## Apple signing setup

With paid Apple Developer Program membership, configure the following once so the
`publish` operation can sign and notarize. The certificate and API key belong to
Apple Team `96NH8UVPYB` (the same team as the iOS and widget targets):

1. Create a **Developer ID Application** certificate and export it from
   Keychain Access as a password-protected `.p12` file.
2. Create an App Store Connect API key for notarization and download its `.p8`
   file. Record its key ID and issuer ID.
3. Base64-encode the two files without putting their contents in the repository:

   ```bash
   base64 -i DeveloperIDApplication.p12 -o developer-id.p12.base64
   base64 -i AuthKey_KEYID.p8 -o notary-key.p8.base64
   ```

4. Reuse the GitHub environment named `release` in **Settings → Environments**.
5. Add these Apple environment secrets:

   - `DEVELOPER_ID_APPLICATION_P12_BASE64`
   - `DEVELOPER_ID_APPLICATION_PASSWORD`
   - `APPLE_NOTARY_KEY_P8_BASE64`
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_TEAM_ID`

   The workflow continues to inherit the existing repository-level
   `SPARKLE_PRIVATE_KEY`; do not duplicate it into the environment.

   The GitHub CLI can set them without placing values on the command line:

   ```bash
   gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env release < developer-id.p12.base64
   gh secret set APPLE_NOTARY_KEY_P8_BASE64 --env release < notary-key.p8.base64
   gh secret set DEVELOPER_ID_APPLICATION_PASSWORD --env release
   gh secret set APPLE_NOTARY_KEY_ID --env release
   gh secret set APPLE_NOTARY_ISSUER_ID --env release
   gh secret set APPLE_TEAM_ID --env release   # 96NH8UVPYB
   ```

6. Run a dry run and confirm it passes. Only then enable signed publishing:

   ```bash
   gh variable set SIGNED_RELEASES_ENABLED --env release --body true
   ```

Until that variable is exactly `true`, Developer ID publication stops at its
first preflight step, before version files or GitHub state can change.

## Publishing a signed release

```bash
gh workflow run release.yml \
  -f operation=publish \
  -f bump=auto
```

The workflow validates all credentials, tests, prepares the version, exports a
Developer ID-signed app, notarizes and staples it, validates it with `codesign`
and `spctl`, creates the final ZIP, and generates the feed with Sparkle 2.8.1’s
official `generate_appcast` tool. Only after all of those checks pass does it
commit the version, create the tag and prerelease, publish the feed, and deploy
Pages.

Releases are serialized. If `main` moves while a release is being prepared,
the compare-and-swap version commit fails rather than publishing code that was
not tested.

## Repairing the Sparkle feed

If a GitHub release exists but publishing or deploying its feed failed:

```bash
gh workflow run release.yml \
  -f operation=repair-appcast \
  -f tag=v0.29.0
```

Repair downloads the existing ZIP and detects its signature mode. Developer ID
archives must pass strict code-signature, Gatekeeper, and stapler checks;
ad-hoc-signed archives must pass strict code-signature validation and require
`UNSIGNED_RELEASES_ENABLED=true`. Repair then reads the version/build,
regenerates the accumulating feed, and dispatches Pages. It does not create
another release or change source files.

## Checking a run

```bash
gh run list --workflow release.yml --limit 5
gh run watch
gh release list --limit 5
```

For a published version, also confirm that its build appears exactly once in
the live appcast.
