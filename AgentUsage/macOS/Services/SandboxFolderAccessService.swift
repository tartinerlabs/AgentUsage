//
//  SandboxFolderAccessService.swift
//  AgentUsage
//
//  Tracks whether the sandboxed macOS app can read the CLI tools' log directories
//  (`~/.claude`, `~/.codex`, `~/.local/share/opencode`) through Full Disk Access
//  or previously saved security-scoped bookmarks.
//

#if os(macOS)
import Foundation
import AppKit
import AgentUsageKit

/// Tracks local log-directory readability for the sandboxed macOS app.
///
/// Preferred access model: the user grants Full Disk Access in System Settings.
/// The app cannot grant that permission programmatically, so `requestFullAccess()`
/// opens Privacy & Security and `refreshAccessStatus()` re-probes afterwards.
///
/// Legacy per-provider and home-folder security-scoped bookmarks from earlier builds
/// are still resolved at launch so upgraders keep access without re-granting.
@MainActor
@Observable
final class SandboxFolderAccessService {
    static let shared = SandboxFolderAccessService()

    /// Providers whose logs require local disk access.
    /// `.openCodeGo` is remote-only, so it is not included.
    static let grantableProviders: [Provider] = [.claude, .codex, .openCode]

    /// Whether the app appears to have broad access to the real home directory.
    private(set) var hasFullAccess = false

    /// Whether any broad or legacy provider-specific access is currently available.
    var hasAnyAccess: Bool {
        hasFullAccess || !legacyScopedURLs.isEmpty
    }

    /// The home URL whose security scope we are holding open, if a previous build saved one.
    private var homeScopedURL: URL?

    /// Legacy per-provider scoped URLs resolved from earlier builds' bookmarks.
    private var legacyScopedURLs: [Provider: URL] = [:]

    private let defaults: UserDefaults
    private let fileManager: FileManager

    private init(defaults: UserDefaults? = nil, fileManager: FileManager = .default) {
        self.defaults = defaults ?? UserDefaults(suiteName: Constants.appGroupIdentifier) ?? .standard
        self.fileManager = fileManager
        resolveExistingGrants()
        refreshAccessStatus()
    }

    // MARK: - Public API

    /// The real directory used by a provider (e.g. real `~/.claude`).
    func defaultDirectory(for provider: Provider) -> URL {
        switch provider {
        case .claude: Constants.claudeHomeDirectory
        case .codex: Constants.codexHomeDirectory
        case .openCode, .openCodeGo: Constants.openCodeHomeDirectory
        }
    }

    /// Whether a provider's logs are readable through Full Disk Access or a legacy bookmark.
    func hasAccess(to provider: Provider) -> Bool {
        hasFullAccess || legacyScopedURLs[provider] != nil || canReadDirectory(defaultDirectory(for: provider))
    }

    /// Open System Settings to Full Disk Access. macOS requires the user to complete
    /// the grant there; this method cannot grant access by itself.
    @discardableResult
    func requestFullAccess() -> Bool {
        openFullDiskAccessSettings()
        refreshAccessStatus()
        return hasFullAccess
    }

    /// Re-check whether Full Disk Access or saved bookmarks currently make the real
    /// home/log directories readable. Call this after the user returns from Settings.
    func refreshAccessStatus() {
        hasFullAccess = homeScopedURL != nil || canReadDirectory(Constants.realHomeDirectory)
    }

    /// Stop holding and forget any saved security-scoped bookmarks from previous
    /// builds. Full Disk Access itself can only be revoked in System Settings.
    func clearSavedFolderGrants() {
        if let url = homeScopedURL {
            url.stopAccessingSecurityScopedResource()
            homeScopedURL = nil
        }
        defaults.removeObject(forKey: homeBookmarkKey)
        hasFullAccess = false
        clearLegacyGrants()
        refreshAccessStatus()
    }

    /// Backwards-compatible name for existing callers; this only clears saved
    /// bookmarks and cannot revoke Full Disk Access.
    func revokeAccess() {
        clearSavedFolderGrants()
    }

    // MARK: - Launch resolution

    /// Resolve persisted bookmarks from earlier builds and begin holding their scopes.
    private func resolveExistingGrants() {
        if let bookmark = defaults.data(forKey: homeBookmarkKey) {
            resolve(bookmark: bookmark, key: homeBookmarkKey) { [weak self] url in
                self?.startHomeAccess(url: url)
            }
        }

        // Legacy fallback: earlier builds stored one bookmark per provider. Keep
        // resolving them until the user grants broader access.
        guard homeScopedURL == nil else { return }
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

    @discardableResult
    private func openFullDiskAccessSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    private func canReadDirectory(_ url: URL) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants]
            )
            return true
        } catch {
            return false
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
    // releases held security scopes automatically on termination. `clearSavedFolderGrants`
    // handles the only case where a scope is released during the app's lifetime.
}
#endif
