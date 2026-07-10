# Releasing ClaudeMeter

ClaudeMeter uses a manually triggered GitHub Actions workflow. “Manual” only
means a person chooses when a release starts; the workflow still handles the
version, tests, signing, notarization, packaging, Sparkle feed, tag, and GitHub
release.

Public releases are currently paused until a Developer ID certificate and
Apple notarization credentials are available. The committed `0.26.0` build
`79` remains the next release candidate and must not be published unsigned.

## The moving pieces

- **CI** builds and tests ordinary pushes and pull requests. It never publishes.
- **Developer ID signing** gives the app a stable identity that Gatekeeper can
  trust when it is downloaded outside the Mac App Store.
- **Notarization** submits the signed app to Apple for automated security
  checks. The resulting ticket is stapled to the app before the final ZIP is
  created.
- **Sparkle** signs the ZIP with a separate EdDSA key and maintains
  `appcast.xml`, which tells installed copies that an update exists.
- **GitHub Pages** serves the appcast at
  `https://tartinerlabs.github.io/ClaudeMeter/appcast.xml`.

Developer ID and Sparkle signatures solve different problems. A production
release requires both.

## Running a dry run

A dry run is safe before the Apple membership is ready:

```bash
gh workflow run release.yml \
  -f operation=dry-run \
  -f bump=auto
```

It calculates the version and notes, runs the macOS tests, simulates changes to
the version files and changelog, and creates an unsigned validation build. Its
job token is read-only, and it contains no publishing steps.

Use `patch`, `minor`, or `major` instead of `auto` to force a bump. An untagged
configured version, such as the current `0.26.0` build `79`, is always resumed
instead of bumped again.

## One-time Apple setup

After joining the Apple Developer Program:

1. Create a **Developer ID Application** certificate and export it from
   Keychain Access as a password-protected `.p12` file.
2. Create an App Store Connect API key for notarization and download its `.p8`
   file. Record its key ID and issuer ID.
3. Base64-encode the two files without putting their contents in the repository:

   ```bash
   base64 -i DeveloperIDApplication.p12 -o developer-id.p12.base64
   base64 -i AuthKey_KEYID.p8 -o notary-key.p8.base64
   ```

4. Create a GitHub environment named `release` in **Settings → Environments**.
5. Add these environment secrets:

   - `DEVELOPER_ID_APPLICATION_P12_BASE64`
   - `DEVELOPER_ID_APPLICATION_PASSWORD`
   - `APPLE_NOTARY_KEY_P8_BASE64`
   - `APPLE_NOTARY_KEY_ID`
   - `APPLE_NOTARY_ISSUER_ID`
   - `APPLE_TEAM_ID`
   - `SPARKLE_PRIVATE_KEY` (set it again from the original secure Sparkle key export; GitHub cannot reveal an existing secret)

   The GitHub CLI can set them without placing values on the command line:

   ```bash
   gh secret set DEVELOPER_ID_APPLICATION_P12_BASE64 --env release < developer-id.p12.base64
   gh secret set APPLE_NOTARY_KEY_P8_BASE64 --env release < notary-key.p8.base64
   gh secret set DEVELOPER_ID_APPLICATION_PASSWORD --env release
   gh secret set APPLE_NOTARY_KEY_ID --env release
   gh secret set APPLE_NOTARY_ISSUER_ID --env release
   gh secret set APPLE_TEAM_ID --env release
   gh secret set SPARKLE_PRIVATE_KEY --env release
   ```

6. Run a dry run and confirm it passes. Only then enable publishing:

   ```bash
   gh variable set SIGNED_RELEASES_ENABLED --env release --body true
   ```

Until that variable is exactly `true`, publish and repair operations stop at
their first preflight step, before version files or GitHub state can change.

## Publishing

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

If a signed GitHub release exists but publishing or deploying its feed failed:

```bash
gh workflow run release.yml \
  -f operation=repair-appcast \
  -f tag=v0.26.0
```

Repair downloads the existing ZIP, verifies its Developer ID signature and
Gatekeeper acceptance, reads its version/build information, regenerates the
accumulating feed, and dispatches Pages. It does not create another release or
change source files.

## Checking a run

```bash
gh run list --workflow release.yml --limit 5
gh run watch
gh release list --limit 5
```

For a published version, also confirm that its build appears exactly once in
the live appcast.
