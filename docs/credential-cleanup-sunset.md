# Sunset the legacy Claude credential cleanup

`KeychainHelper.deleteLegacyClaudeCredentials()` is a temporary migration. It
removes Agent Usage's obsolete Claude credential copy from its own Keychain
service, including synchronizable copies. It never deletes Claude Code or Claude
Desktop credentials.

The migration runs once per app defaults domain. A successful deletion or an
absent item marks it complete; other failures retry on the next launch. Test
launches skip real Keychain cleanup.

## Release anchor

Fill in these fields when the first production release containing the cleanup
ships. Repository version settings alone do not establish the release anchor.

- First cleanup release version/build: pending
- First cleanup release date: pending
- Two subsequent production releases: pending
- Earliest removal date, 90 days after the first cleanup release: pending

Keep the migration for at least two subsequent production releases and 90 days
after the first cleanup release, whichever is later. Beta builds do not count as
subsequent production releases. Apply the retention window to both macOS and iOS;
if they ship separately, wait until both platforms meet the criteria.

## Removal checklist

- Confirm both retention criteria have been met on both platforms.
- Confirm macOS no longer mirrors Claude credentials or falls back to the synced
  copy, and iOS still consumes only Mac-published CloudKit snapshots.
- Confirm no production code reads or writes the legacy
  `com.tartinerlabs.AgentUsage` / `claude-oauth-credentials` item.
- Remove the startup call in `AgentUsageApp.init()`, the cleanup function and its
  TODO, and `LegacyClaudeCredentialCleanupTests` together.
- Leave `legacyClaudeCredentialCleanupCompleted` inert in existing defaults;
  removing this flag does not require another migration.
- Run the macOS unit suite and iOS unit suite, including CloudKit refresh tests.
- Record the removal release and date in this document.

## Late upgrades

Users who skip every release containing the migration may retain the old Keychain
copy. Updated Agent Usage builds never read or use it, but automatic deletion is
not guaranteed after this migration is removed. Retain the migration indefinitely
instead if cleanup for every late upgrader becomes a requirement.

## Removal record

- Removal release version/build: pending
- Removal date: pending
