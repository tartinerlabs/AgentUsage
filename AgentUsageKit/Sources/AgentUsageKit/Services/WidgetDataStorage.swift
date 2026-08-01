//
//  WidgetDataStorage.swift
//  AgentUsageKit
//
//  Shared widget data storage for cross-process communication via App Groups
//

import Foundation

/// Versioned provider-neutral data handed to WidgetKit.
///
/// `UsageSnapshot` predates multi-provider support and has fixed Claude fields.
/// Keeping the widget payload separate lets WidgetKit render provider-defined
/// windows (including Cursor's dynamic identifiers) without changing that legacy
/// API model.
public struct WidgetUsagePayload: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let providerSnapshots: [ProviderUsageSnapshot]

    public init(
        snapshot: UsageSnapshot? = nil,
        providerSnapshots: [ProviderUsageSnapshot],
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.providerSnapshots = Self.normalized(
            snapshot: snapshot,
            providerSnapshots: providerSnapshots
        )
    }

    public func snapshot(for provider: Provider) -> ProviderUsageSnapshot? {
        providerSnapshots.first { $0.provider == provider }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providerSnapshots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        let snapshots = try container.decode([ProviderUsageSnapshot].self, forKey: .providerSnapshots)
        providerSnapshots = Self.normalized(snapshot: nil, providerSnapshots: snapshots)
    }

    private static func normalized(
        snapshot: UsageSnapshot?,
        providerSnapshots: [ProviderUsageSnapshot]
    ) -> [ProviderUsageSnapshot] {
        // Modern provider snapshots are authoritative. The fixed Claude payload is
        // bridged only for records written by older app versions.
        var snapshotsByProvider: [Provider: ProviderUsageSnapshot] = [:]
        for providerSnapshot in providerSnapshots {
            snapshotsByProvider[providerSnapshot.provider] = providerSnapshot
        }
        if snapshotsByProvider[.claude] == nil, let snapshot {
            snapshotsByProvider[.claude] = ProviderUsageSnapshot(claude: snapshot)
        }

        return Provider.allCases.compactMap { snapshotsByProvider[$0] }
    }
}

/// Shared App Group storage used by the iOS app and widget extension.
public final class WidgetDataStorage: Sendable {
    public static let shared = WidgetDataStorage()

    public static let suiteName = "group.com.tartinerlabs.AgentUsage"

    /// Legacy Claude-only key. Retained so already-installed widgets migrate.
    public static let snapshotKey = "cachedUsageSnapshot"

    /// Current provider-neutral payload key.
    public static let payloadKey = "cachedWidgetUsagePayload"

    private let suiteName: String

    /// A custom suite is accepted so persistence and migration can be tested
    /// without touching the real App Group.
    public init(suiteName: String = WidgetDataStorage.suiteName) {
        self.suiteName = suiteName
    }

    /// Load the current payload, falling back to the legacy Claude snapshot.
    public func loadPayload() -> WidgetUsagePayload? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }

        if let data = defaults.data(forKey: Self.payloadKey),
           let payload = try? JSONDecoder().decode(WidgetUsagePayload.self, from: data) {
            return payload
        }

        guard let snapshot = loadLegacySnapshot(from: defaults) else { return nil }
        return WidgetUsagePayload(snapshot: snapshot, providerSnapshots: [])
    }

    /// Provider snapshots available to WidgetKit, in canonical provider order.
    public func loadProviderSnapshots() -> [ProviderUsageSnapshot] {
        loadPayload()?.providerSnapshots ?? []
    }

    /// Legacy compatibility accessor. New widget code should use `loadPayload()`.
    public func load() -> UsageSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        if let snapshot = loadLegacySnapshot(from: defaults) {
            return snapshot
        }
        guard let claude = loadPayload()?.snapshot(for: .claude) else { return nil }
        return Self.legacySnapshot(from: claude)
    }

    /// Save a provider-neutral payload. The legacy key is dual-written when a
    /// complete Claude snapshot is present and removed for provider-only updates,
    /// preventing stale Claude data from surviving a newer Codex/Cursor refresh.
    @discardableResult
    public func save(_ payload: WidgetUsagePayload) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }

        do {
            let payloadData = try JSONEncoder().encode(payload)
            let legacyData = try payload.snapshot(for: .claude)
                .flatMap(Self.legacySnapshot(from:))
                .map { try JSONEncoder().encode($0) }

            defaults.set(payloadData, forKey: Self.payloadKey)
            if let legacyData {
                defaults.set(legacyData, forKey: Self.snapshotKey)
            } else {
                defaults.removeObject(forKey: Self.snapshotKey)
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func save(_ providerSnapshots: [ProviderUsageSnapshot]) -> Bool {
        save(WidgetUsagePayload(providerSnapshots: providerSnapshots))
    }

    /// Legacy compatibility writer. It also seeds the provider-neutral payload.
    @discardableResult
    public func save(_ snapshot: UsageSnapshot) -> Bool {
        save(WidgetUsagePayload(snapshot: snapshot, providerSnapshots: []))
    }

    public func clear() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.removeObject(forKey: Self.payloadKey)
        defaults.removeObject(forKey: Self.snapshotKey)
    }

    private func loadLegacySnapshot(from defaults: UserDefaults) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    private static func legacySnapshot(from snapshot: ProviderUsageSnapshot) -> UsageSnapshot? {
        guard snapshot.provider == .claude,
              let session = snapshot.windows.first(where: { $0.windowID.rawValue == UsageWindowType.session.rawValue }),
              let opus = snapshot.windows.first(where: { $0.windowID.rawValue == UsageWindowType.opus.rawValue }) else {
            return nil
        }

        func window(_ type: UsageWindowType) -> UsageWindow? {
            snapshot.windows.first { $0.windowID.rawValue == type.rawValue }
        }

        return UsageSnapshot(
            session: session,
            opus: opus,
            sonnet: window(.sonnet),
            design: window(.design),
            fable: window(.fable),
            extraUsage: snapshot.extraUsage,
            fetchedAt: snapshot.fetchedAt
        )
    }
}
