//
//  SandboxFolderAccessService.swift
//  AgentUsage
//
//  Grants the sandboxed macOS app read access to the CLI tools' log directories
//  (`~/.claude`, `~/.codex`, `~/.local/share/opencode`) via user-selected folders
//  and persisted security-scoped bookmarks.
//

#if os(macOS)
import Foundation
import AppKit
import AgentUsageKit

/// Manages user-granted, security-scoped read access to the local log directories
/// that the App Sandbox otherwise hides.
///
/// Access model: bookmarks are persisted in the App Group defaults suite, resolved
/// once at launch, and their security scope is **held for the process lifetime**
/// (`startAccessingSecurityScopedResource` without a matching stop until deinit).
/// This suits a continuously-refreshing menu-bar app and means the file-reading
/// services need no per-read scope wrapping — they read the real paths from
/// `Constants` and access is ambient once `resolveExistingGrants()` has run.
@MainActor
@Observable
final class SandboxFolderAccessService {
    static let shared = SandboxFolderAccessService()

    /// Providers that have a local directory a user can grant access to.
    /// `.openCodeGo` is remote-only, so it is not included.
    static let grantableProviders: [Provider] = [.claude, .codex, .openCode]

    /// Provider ids whose bookmarks are currently resolved and access-started.
    private(set) var grantedProviders: Set<Provider> = []

    /// URLs whose security scope we are holding open, so we can release on deinit.
    private var activeScopedURLs: [Provider: URL] = [:]

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

    func hasAccess(to provider: Provider) -> Bool {
        grantedProviders.contains(provider)
    }

    /// Present an open panel for the provider's directory and, on selection, persist
    /// a security-scoped bookmark and begin holding its scope. Returns whether access
    /// is now granted.
    @discardableResult
    func requestAccess(to provider: Provider) -> Bool {
        let target = defaultDirectory(for: provider)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true          // .claude / .codex are hidden
        panel.directoryURL = target
        panel.message = "Grant read access to \(provider.displayName)'s local usage logs at \(target.path)."
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
            defaults.set(bookmark, forKey: bookmarkDefaultsKey(for: provider))
            startAccess(to: provider, url: url)
            return true
        } catch {
            NSLog("SandboxFolderAccessService: failed to create bookmark for \(provider.rawValue): \(error)")
            return false
        }
    }

    /// Stop holding the scope and forget the stored bookmark for a provider.
    func revokeAccess(to provider: Provider) {
        if let url = activeScopedURLs.removeValue(forKey: provider) {
            url.stopAccessingSecurityScopedResource()
        }
        defaults.removeObject(forKey: bookmarkDefaultsKey(for: provider))
        grantedProviders.remove(provider)
    }

    // MARK: - Launch resolution

    /// Resolve every persisted bookmark and begin holding its scope. Called once at
    /// init; re-creates stale bookmarks opportunistically.
    private func resolveExistingGrants() {
        for provider in Self.grantableProviders {
            guard let bookmark = defaults.data(forKey: bookmarkDefaultsKey(for: provider)) else {
                continue
            }
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                startAccess(to: provider, url: url)

                if isStale {
                    // Refresh the bookmark while we hold the scope, so it keeps resolving.
                    if let refreshed = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        defaults.set(refreshed, forKey: bookmarkDefaultsKey(for: provider))
                    }
                }
            } catch {
                NSLog("SandboxFolderAccessService: failed to resolve bookmark for \(provider.rawValue): \(error)")
            }
        }
    }

    private func startAccess(to provider: Provider, url: URL) {
        // Release any prior scope for this provider before replacing it.
        if let previous = activeScopedURLs.removeValue(forKey: provider) {
            previous.stopAccessingSecurityScopedResource()
        }
        if url.startAccessingSecurityScopedResource() {
            activeScopedURLs[provider] = url
            grantedProviders.insert(provider)
        } else {
            NSLog("SandboxFolderAccessService: startAccessingSecurityScopedResource failed for \(provider.rawValue)")
        }
    }

    private func bookmarkDefaultsKey(for provider: Provider) -> String {
        "sandboxFolderBookmark.\(provider.rawValue)"
    }

    // No deinit cleanup: this is a process-lifetime singleton, and the sandbox
    // releases held security scopes automatically on termination. `revokeAccess`
    // handles the only case where a scope is released during the app's lifetime.
}
#endif
