//
//  SandboxFolderAccessService.swift
//  AgentUsage
//
//  Grants the sandboxed macOS app read access to the CLI tools' log directories
//  (`~/.claude`, `~/.codex`, `~/.local/share/opencode`) via a single, one-time
//  user-selected home-folder grant and a persisted security-scoped bookmark.
//

#if os(macOS)
import Foundation
import AppKit
import AgentUsageKit

/// Manages a single user-granted, security-scoped read grant covering the home
/// directory, which the App Sandbox otherwise hides.
///
/// Access model: the user grants read access to their home folder **once**. That
/// one grant covers every provider's log directory (all are subpaths of home).
/// The bookmark is persisted in the App Group defaults suite, resolved once at
/// launch, and its security scope is **held for the process lifetime**
/// (`startAccessingSecurityScopedResource` without a matching stop until deinit).
/// This suits a continuously-refreshing menu-bar app and means the file-reading
/// services need no per-read scope wrapping — they read the real paths from
/// `Constants` and access is ambient once `resolveExistingGrants()` has run.
///
/// Legacy per-provider bookmarks from earlier builds are still resolved at launch
/// so upgraders keep access without re-granting.
@MainActor
@Observable
final class SandboxFolderAccessService {
    static let shared = SandboxFolderAccessService()

    /// Providers whose logs are covered once home access is granted.
    /// `.openCodeGo` is remote-only, so it is not included.
    static let grantableProviders: [Provider] = [.claude, .codex, .openCode]

    /// Whether the single home-folder grant is currently resolved and access-started.
    private(set) var hasFullAccess = false

    /// The home URL whose security scope we are holding open, if granted.
    private var homeScopedURL: URL?

    /// Legacy per-provider scoped URLs resolved from earlier builds' bookmarks.
    private var legacyScopedURLs: [Provider: URL] = [:]

    private let defaults: UserDefaults

    private init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Constants.appGroupIdentifier) ?? .standard
        resolveExistingGrants()
    }

    // MARK: - Public API

    /// The real directory a grant covers for a provider (e.g. real `~/.claude`).
    func defaultDirectory(for provider: Provider) -> URL {
        switch provider {
        case .claude: Constants.claudeHomeDirectory
        case .codex: Constants.codexHomeDirectory
        case .openCode, .openCodeGo: Constants.openCodeHomeDirectory
        }
    }

    /// Whether a provider's logs are readable — true when the home grant is active,
    /// or when a legacy per-provider grant from an earlier build is still resolved.
    func hasAccess(to provider: Provider) -> Bool {
        hasFullAccess || legacyScopedURLs[provider] != nil
    }

    /// Present a single open panel defaulting to the user's home folder and, on
    /// selection, persist a security-scoped bookmark and begin holding its scope.
    /// This one grant covers every provider. Returns whether access is now granted.
    @discardableResult
    func requestFullAccess() -> Bool {
        let target = Constants.realHomeDirectory

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true          // logs live in hidden dot-directories
        panel.directoryURL = target
        panel.message = "Grant read access to your home folder so \(Constants.appDisplayName) "
            + "can read the local usage logs for Claude, Codex, and OpenCode. This is asked only once."
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: homeBookmarkKey)
            startHomeAccess(url: url)
            // The home grant supersedes any legacy per-provider grants; drop them.
            clearLegacyGrants()
            return hasFullAccess
        } catch {
            NSLog("SandboxFolderAccessService: failed to create home bookmark: \(error)")
            return false
        }
    }

    /// Stop holding the home scope and forget the stored bookmark (and any legacy
    /// per-provider bookmarks).
    func revokeAccess() {
        if let url = homeScopedURL {
            url.stopAccessingSecurityScopedResource()
            homeScopedURL = nil
        }
        defaults.removeObject(forKey: homeBookmarkKey)
        hasFullAccess = false
        clearLegacyGrants()
    }

    // MARK: - Launch resolution

    /// Resolve the persisted home bookmark and begin holding its scope. Called once
    /// at init; falls back to legacy per-provider bookmarks so upgraders keep access.
    private func resolveExistingGrants() {
        if let bookmark = defaults.data(forKey: homeBookmarkKey) {
            resolve(bookmark: bookmark, key: homeBookmarkKey) { [weak self] url in
                self?.startHomeAccess(url: url)
            }
        }

        // Legacy fallback: earlier builds stored one bookmark per provider. Keep
        // resolving them until the user grants the unified home access.
        guard !hasFullAccess else { return }
        for provider in Self.grantableProviders {
            let key = legacyBookmarkKey(for: provider)
            guard let bookmark = defaults.data(forKey: key) else { continue }
            resolve(bookmark: bookmark, key: key) { [weak self] url in
                if url.startAccessingSecurityScopedResource() {
                    self?.legacyScopedURLs[provider] = url
                }
            }
        }
    }

    /// Resolve a security-scoped bookmark, refreshing it in place if stale, and hand
    /// the resulting URL to `onResolved`.
    private func resolve(bookmark: Data, key: String, onResolved: (URL) -> Void) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            onResolved(url)

            if isStale, let refreshed = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(refreshed, forKey: key)
            }
        } catch {
            NSLog("SandboxFolderAccessService: failed to resolve bookmark \(key): \(error)")
        }
    }

    private func startHomeAccess(url: URL) {
        // Release any prior scope before replacing it.
        if let previous = homeScopedURL {
            previous.stopAccessingSecurityScopedResource()
            homeScopedURL = nil
        }
        if url.startAccessingSecurityScopedResource() {
            homeScopedURL = url
            hasFullAccess = true
        } else {
            NSLog("SandboxFolderAccessService: startAccessingSecurityScopedResource failed for home")
        }
    }

    private func clearLegacyGrants() {
        for (provider, url) in legacyScopedURLs {
            url.stopAccessingSecurityScopedResource()
            defaults.removeObject(forKey: legacyBookmarkKey(for: provider))
        }
        legacyScopedURLs.removeAll()
    }

    private let homeBookmarkKey = "sandboxFolderBookmark.home"

    private func legacyBookmarkKey(for provider: Provider) -> String {
        "sandboxFolderBookmark.\(provider.rawValue)"
    }

    // No deinit cleanup: this is a process-lifetime singleton, and the sandbox
    // releases held security scopes automatically on termination. `revokeAccess`
    // handles the only case where a scope is released during the app's lifetime.
}
#endif
