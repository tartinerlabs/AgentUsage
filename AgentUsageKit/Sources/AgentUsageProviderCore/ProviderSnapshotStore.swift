import AgentUsageKit
import Foundation

public struct ProviderSnapshotEnvelope: Codable, Sendable {
    public static let currentVersion = 2

    public let version: Int
    public let savedAt: Date
    public let states: [ProviderRuntimeState]

    public init(
        version: Int = Self.currentVersion,
        savedAt: Date = Date(),
        states: [ProviderRuntimeState]
    ) {
        self.version = version
        self.savedAt = savedAt
        self.states = states
    }

    public var statesByProvider: [Provider: ProviderRuntimeState] {
        Dictionary(uniqueKeysWithValues: states.map { ($0.provider, $0) })
    }

    public static func migratingLegacyClaude(
        _ snapshot: UsageSnapshot,
        planName: String? = nil
    ) -> ProviderSnapshotEnvelope {
        let providerSnapshot = ProviderUsageSnapshot(claude: snapshot, planName: planName)
        return ProviderSnapshotEnvelope(states: [
            ProviderRuntimeState(
                provider: .claude,
                snapshot: providerSnapshot,
                sourceLabel: "legacy-cache",
                freshness: .stale,
                generation: 0,
                lastSuccessfulAt: snapshot.fetchedAt
            ).evaluated(at: Date())
        ])
    }
}

public actor ProviderSnapshotStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func load() throws -> ProviderSnapshotEnvelope? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try decoder.decode(ProviderSnapshotEnvelope.self, from: data)
        guard envelope.version <= ProviderSnapshotEnvelope.currentVersion else {
            throw ProviderSnapshotStoreError.unsupportedVersion(envelope.version)
        }
        return envelope
    }

    @discardableResult
    public func loadOrMigrate(
        legacyClaudeSnapshot: UsageSnapshot?,
        legacyPlanName: String? = nil
    ) throws -> ProviderSnapshotEnvelope? {
        if let existing = try load() { return existing }
        guard let legacyClaudeSnapshot else { return nil }
        let migrated = ProviderSnapshotEnvelope.migratingLegacyClaude(
            legacyClaudeSnapshot,
            planName: legacyPlanName
        )
        try save(migrated)
        return migrated
    }

    public func save(_ envelope: ProviderSnapshotEnvelope) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

public enum ProviderSnapshotStoreError: Error, Sendable {
    case unsupportedVersion(Int)
}
