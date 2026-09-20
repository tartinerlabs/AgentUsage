//
//  UsageSyncService.swift
//  AgentUsageKit
//
//  Cross-device usage sync via CloudKit.
//
//  macOS is the single source of truth: it fetches usage from the provider
//  endpoints and publishes the resulting UsageSnapshot to the user's private
//  CloudKit database. iPhone and iPad fetch that snapshot and acknowledge the
//  exact sync generation they received. macOS uses those receipts to show a
//  verified round trip instead of inferring connectivity from local data.
//
//  Production uses CKSyncEngine for sends and scheduled pulls. Widget
//  extensions and tests never create the engine: widgets do a one-shot record
//  read, and tests inject an in-memory database.
//

#if canImport(CloudKit)
import CloudKit
import Foundation
import OSLog

public enum UsageSyncDevice: String, CaseIterable, Codable, Hashable, Sendable {
    case iPhone
    case iPad
}

public struct PublishedUsageSnapshot: Equatable, Sendable {
    public let syncGeneration: String
    public let fetchedAt: Date

    public init(syncGeneration: String, fetchedAt: Date) {
        self.syncGeneration = syncGeneration
        self.fetchedAt = fetchedAt
    }
}

/// A usage snapshot received from another device via CloudKit, tagged with the
/// time the source device fetched it and the generation used for acknowledgement.
public struct SyncedUsageSnapshot: Sendable {
    public let snapshot: UsageSnapshot?
    public let planType: String
    public let providerSnapshots: [ProviderUsageSnapshot]
    /// When the source device fetched this from the provider (not when it synced).
    public let fetchedAt: Date
    /// Nil for records written by builds released before verified receipts existed.
    public let syncGeneration: String?

    public init(
        snapshot: UsageSnapshot? = nil,
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot] = [],
        fetchedAt: Date,
        syncGeneration: String? = nil
    ) {
        self.snapshot = snapshot
        self.planType = planType
        self.providerSnapshots = providerSnapshots
        self.fetchedAt = fetchedAt
        self.syncGeneration = syncGeneration
    }

    /// Seconds since the source device fetched this snapshot.
    public func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}

public struct ContinuityReceipt: Equatable, Sendable {
    public let device: UsageSyncDevice
    public let syncGeneration: String
    public let acknowledgedAt: Date

    public init(device: UsageSyncDevice, syncGeneration: String, acknowledgedAt: Date) {
        self.device = device
        self.syncGeneration = syncGeneration
        self.acknowledgedAt = acknowledgedAt
    }
}

public enum UsageSyncError: LocalizedError, Equatable, Sendable {
    case missingRecordResult(recordName: String)
    case recordOperationFailed(recordName: String, message: String)
    case invalidRecord(recordName: String, reason: String)
    case missingSyncGeneration

    public var errorDescription: String? {
        switch self {
        case .missingRecordResult(let recordName):
            return "CloudKit returned no result for \(recordName)."
        case .recordOperationFailed(let recordName, let message):
            return "CloudKit operation failed for \(recordName): \(message)"
        case .invalidRecord(let recordName, let reason):
            return "CloudKit record \(recordName) is invalid: \(reason)"
        case .missingSyncGeneration:
            return "The shared usage snapshot predates verified device acknowledgements."
        }
    }
}

public protocol UsageSyncServicing: Sendable {
    func publish(
        snapshot: UsageSnapshot?,
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot]
    ) async throws -> PublishedUsageSnapshot
    func fetchLatest() async -> SyncedUsageSnapshot?
    func acknowledge(
        snapshot: SyncedUsageSnapshot,
        from device: UsageSyncDevice
    ) async throws -> ContinuityReceipt
    func fetchReceipts() async throws -> [UsageSyncDevice: ContinuityReceipt]
    func revokeAll() async -> Bool
    func revoke(device: UsageSyncDevice) async -> Bool
    func ensureSnapshotSubscription() async throws
    func deleteSnapshotSubscription() async -> Bool
}

protocol UsageSyncDatabase: AnyObject, Sendable {
    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>]

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, Error>],
        deleteResults: [CKRecord.ID: Result<Void, Error>]
    )

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID
}

extension CKDatabase: UsageSyncDatabase {}

/// Publishes and reads the latest usage snapshot through the user's private
/// CloudKit database. Reads remain best-effort so callers can use cached data;
/// writes throw when either the batch or the target record fails.
public actor UsageSyncService: UsageSyncServicing {
    public static let shared = UsageSyncService()

    /// CloudKit container. Must match the iCloud container entitlement on every target.
    public static let containerIdentifier = "iCloud.com.tartinerlabs.AgentUsage"

    /// Legacy query-subscription ID from the pre-CKSyncEngine path. Kept so
    /// existing installs can delete it after the engine takes over silent push.
    public static let snapshotSubscriptionID: CKSubscription.ID = "usage-snapshot-silent-push"

    static let zoneID = CKRecordZone.ID(zoneName: "Continuity")

    private static let snapshotRecordType = "UsageSnapshot"
    private static let snapshotRecordName = "latest"
    private static let receiptRecordType = "ContinuityReceipt"
    private static let payloadKey = "payload"
    private static let planTypeKey = "planType"
    private static let providerSnapshotsKey = "providerSnapshots"
    private static let fetchedAtKey = "fetchedAt"
    private static let syncGenerationKey = "syncGeneration"
    private static let deviceKindKey = "deviceKind"
    private static let acknowledgedAtKey = "acknowledgedAt"
    private static let engineStateFilename = "ContinuitySyncEngineState.json"

    private var injectedDatabase: (any UsageSyncDatabase)?
    private var cloudDatabase: CKDatabase?
    private let containerIdentifier: String?
    private let snapshotRecordID: CKRecord.ID
    private let logger = Logger(subsystem: "com.tartinerlabs.AgentUsage", category: "UsageSync")

    private var syncEngine: CKSyncEngine?
    private var lastKnownRecords: [CKRecord.ID: CKRecord] = [:]
    private var sendFailure: UsageSyncError?
    private let usesEngine: Bool

    public init(containerIdentifier: String = UsageSyncService.containerIdentifier) {
        self.injectedDatabase = nil
        self.containerIdentifier = containerIdentifier
        self.snapshotRecordID = Self.makeSnapshotRecordID()
        self.usesEngine = !Self.isAppExtension
    }

    init(database: any UsageSyncDatabase) {
        self.injectedDatabase = database
        self.containerIdentifier = nil
        self.snapshotRecordID = Self.makeSnapshotRecordID()
        self.usesEngine = false
    }

    /// Publish the latest snapshot, overwriting the previous one. The returned
    /// generation becomes connected only after a mobile receipt echoes it.
    public func publish(
        snapshot: UsageSnapshot?,
        planType: String,
        providerSnapshots: [ProviderUsageSnapshot] = []
    ) async throws -> PublishedUsageSnapshot {
        let generation = UUID().uuidString
        let fetchedAt = snapshot?.fetchedAt
            ?? providerSnapshots.map(\.fetchedAt).max()
            ?? Date()

        do {
            let record = lastKnownRecords[snapshotRecordID]
                ?? CKRecord(recordType: Self.snapshotRecordType, recordID: snapshotRecordID)
            if let snapshot {
                record[Self.payloadKey] = try JSONEncoder().encode(snapshot) as CKRecordValue
            } else {
                record[Self.payloadKey] = nil
            }
            record[Self.planTypeKey] = planType as CKRecordValue
            record[Self.providerSnapshotsKey] = try JSONEncoder().encode(providerSnapshots) as CKRecordValue
            record[Self.fetchedAtKey] = fetchedAt as CKRecordValue
            record[Self.syncGenerationKey] = generation as CKRecordValue

            _ = try await save(record)
            logger.debug("Published usage snapshot generation \(generation, privacy: .public)")
            return PublishedUsageSnapshot(syncGeneration: generation, fetchedAt: fetchedAt)
        } catch {
            let syncError = Self.syncError(error, recordName: snapshotRecordID.recordName)
            logger.error("CloudKit publish failed: \(syncError.localizedDescription, privacy: .public)")
            throw syncError
        }
    }

    /// Fetch the most recently published snapshot. Legacy records without a
    /// generation remain readable but cannot be acknowledged.
    public func fetchLatest() async -> SyncedUsageSnapshot? {
        if usesEngine {
            startEngineIfNeeded()
            await fetchEngineChanges()
        }

        if let synced = await readSnapshot(id: snapshotRecordID) {
            return synced
        }
        return await readSnapshot(id: CKRecord.ID(recordName: Self.snapshotRecordName))
    }

    /// Record that a mobile device successfully received this exact generation.
    @discardableResult
    public func acknowledge(
        snapshot: SyncedUsageSnapshot,
        from device: UsageSyncDevice
    ) async throws -> ContinuityReceipt {
        guard let generation = snapshot.syncGeneration else {
            throw UsageSyncError.missingSyncGeneration
        }

        let receipt = ContinuityReceipt(
            device: device,
            syncGeneration: generation,
            acknowledgedAt: Date()
        )
        let recordID = Self.receiptRecordID(for: device)
        let record = lastKnownRecords[recordID]
            ?? CKRecord(recordType: Self.receiptRecordType, recordID: recordID)
        record[Self.deviceKindKey] = device.rawValue as CKRecordValue
        record[Self.syncGenerationKey] = generation as CKRecordValue
        record[Self.acknowledgedAtKey] = receipt.acknowledgedAt as CKRecordValue

        do {
            _ = try await save(record)
            logger.debug(
                "Acknowledged generation \(generation, privacy: .public) from \(device.rawValue, privacy: .public)"
            )
            return receipt
        } catch {
            let syncError = Self.syncError(error, recordName: recordID.recordName)
            logger.error("CloudKit acknowledgement failed: \(syncError.localizedDescription, privacy: .public)")
            throw syncError
        }
    }

    /// Fetch the latest acknowledgement for each mobile device family. A missing
    /// fixed-ID record means that family has never acknowledged a snapshot.
    public func fetchReceipts() async throws -> [UsageSyncDevice: ContinuityReceipt] {
        if usesEngine {
            startEngineIfNeeded()
            await fetchEngineChanges()
        }

        let recordIDs = UsageSyncDevice.allCases.map(Self.receiptRecordID(for:))

        do {
            let results = try await resolvedDatabase().records(for: recordIDs, desiredKeys: nil)
            var receipts: [UsageSyncDevice: ContinuityReceipt] = [:]

            for device in UsageSyncDevice.allCases {
                let recordID = Self.receiptRecordID(for: device)
                guard let result = results[recordID] else {
                    throw UsageSyncError.missingRecordResult(recordName: recordID.recordName)
                }

                do {
                    let record = try result.get()
                    lastKnownRecords[recordID] = record
                    receipts[device] = try Self.receipt(from: record, expectedDevice: device)
                } catch where Self.isUnknownItem(error) {
                    continue
                }
            }

            return receipts
        } catch {
            let syncError = Self.syncError(error, recordName: Self.receiptRecordType)
            logger.error("CloudKit receipt fetch failed: \(syncError.localizedDescription, privacy: .public)")
            throw syncError
        }
    }

    /// Start CKSyncEngine so CloudKit silent pushes can pull the Continuity zone.
    /// Idempotent. Widget extensions and tests no-op.
    public func ensureSnapshotSubscription() async throws {
        guard usesEngine else { return }
        startEngineIfNeeded()
    }

    /// Drop the legacy query subscription. CKSyncEngine owns silent push now;
    /// missing subscriptions count as success.
    public func deleteSnapshotSubscription() async -> Bool {
        await deleteLegacyQuerySubscription()
    }

    /// Remove the shared snapshot, all device receipts, and the Continuity zone.
    /// Used by macOS when Continuity Sync is revoked for the whole shared setup.
    public func revokeAll() async -> Bool {
        if usesEngine {
            startEngineIfNeeded()
            guard let syncEngine else { return false }
            syncEngine.state.add(pendingDatabaseChanges: [.deleteZone(Self.zoneID)])
            do {
                try await syncEngine.sendChanges()
                lastKnownRecords.removeAll()
                _ = await deleteLegacyQuerySubscription()
                logger.debug("Revoked Continuity CloudKit zone")
                return true
            } catch {
                logger.error("CloudKit zone revoke failed: \(Self.describe(error), privacy: .public)")
                return false
            }
        }

        let recordsDeleted = await delete(
            recordIDs: [snapshotRecordID] + UsageSyncDevice.allCases.map(Self.receiptRecordID(for:))
        )
        let subscriptionDeleted = await deleteLegacyQuerySubscription()
        return recordsDeleted && subscriptionDeleted
    }

    /// Remove one mobile device's acknowledgement. The account-wide silent-push
    /// subscription stays so Continuity off on iPhone does not stop wakes on a
    /// still-linked iPad. The revoking device no-ops refresh via
    /// `appConnectionRevoked`.
    public func revoke(device: UsageSyncDevice) async -> Bool {
        await delete(recordIDs: [Self.receiptRecordID(for: device)])
    }

    /// Backward-compatible whole-setup revoke for existing callers.
    @discardableResult
    public func revoke() async -> Bool {
        await revokeAll()
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        lastKnownRecords[record.recordID] = record

        if usesEngine {
            startEngineIfNeeded()
            guard let syncEngine else {
                throw UsageSyncError.recordOperationFailed(
                    recordName: record.recordID.recordName,
                    message: "CKSyncEngine is not available."
                )
            }
            sendFailure = nil
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            try await syncEngine.sendChanges()
            if let sendFailure {
                throw sendFailure
            }
            return lastKnownRecords[record.recordID] ?? record
        }

        let database = resolvedDatabase()
        let result = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
        guard let recordResult = result.saveResults[record.recordID] else {
            throw UsageSyncError.missingRecordResult(recordName: record.recordID.recordName)
        }
        let saved = try recordResult.get()
        lastKnownRecords[record.recordID] = saved
        return saved
    }

    private func delete(recordIDs: [CKRecord.ID]) async -> Bool {
        for recordID in recordIDs {
            lastKnownRecords[recordID] = nil
        }

        if usesEngine {
            startEngineIfNeeded()
            guard let syncEngine else { return false }
            sendFailure = nil
            syncEngine.state.add(pendingRecordZoneChanges: recordIDs.map { .deleteRecord($0) })
            do {
                try await syncEngine.sendChanges()
                if let sendFailure {
                    logger.error("CloudKit revoke failed: \(sendFailure.localizedDescription, privacy: .public)")
                    return false
                }
                logger.debug("Revoked requested CloudKit continuity records")
                return true
            } catch {
                logger.error("CloudKit revoke failed: \(Self.describe(error), privacy: .public)")
                return false
            }
        }

        do {
            let database = resolvedDatabase()
            let result = try await database.modifyRecords(
                saving: [],
                deleting: recordIDs,
                savePolicy: .allKeys,
                atomically: false
            )
            var succeeded = true

            for recordID in recordIDs {
                guard let recordResult = result.deleteResults[recordID] else {
                    logger.error("CloudKit returned no delete result for \(recordID.recordName, privacy: .public)")
                    succeeded = false
                    continue
                }

                if case .failure(let error) = recordResult, !Self.isUnknownItem(error) {
                    logger.error(
                        "CloudKit revoke failed for \(recordID.recordName, privacy: .public): \(Self.describe(error), privacy: .public)"
                    )
                    succeeded = false
                }
            }

            if succeeded {
                logger.debug("Revoked requested CloudKit continuity records")
            }
            return succeeded
        } catch {
            logger.error("CloudKit revoke failed: \(Self.describe(error), privacy: .public)")
            return false
        }
    }

    private func readSnapshot(id: CKRecord.ID) async -> SyncedUsageSnapshot? {
        do {
            let results = try await resolvedDatabase().records(for: [id], desiredKeys: nil)
            guard let result = results[id] else {
                throw UsageSyncError.missingRecordResult(recordName: id.recordName)
            }
            let record = try result.get()
            lastKnownRecords[record.recordID] = record

            let snapshot: UsageSnapshot?
            if let payload = record[Self.payloadKey] as? Data {
                snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: payload)
            } else {
                snapshot = nil
            }
            let providerSnapshots = try Self.providerSnapshots(from: record)
            guard snapshot != nil || !providerSnapshots.isEmpty else {
                throw UsageSyncError.invalidRecord(
                    recordName: id.recordName,
                    reason: "missing payload"
                )
            }
            let planType = record[Self.planTypeKey] as? String ?? "Free"
            let fetchedAt = record[Self.fetchedAtKey] as? Date
                ?? snapshot?.fetchedAt
                ?? providerSnapshots.map(\.fetchedAt).max()
                ?? Date()
            let generation = record[Self.syncGenerationKey] as? String
            return SyncedUsageSnapshot(
                snapshot: snapshot,
                planType: planType,
                providerSnapshots: providerSnapshots,
                fetchedAt: fetchedAt,
                syncGeneration: generation
            )
        } catch {
            if Self.isUnknownItem(error) {
                logger.debug("CloudKit fetch: no snapshot published yet")
            } else {
                logger.error("CloudKit fetch failed: \(Self.describe(error), privacy: .public)")
            }
            return nil
        }
    }

    private func startEngineIfNeeded() {
        guard usesEngine, syncEngine == nil else { return }
        var configuration = CKSyncEngine.Configuration(
            database: ckDatabase(),
            stateSerialization: Self.loadEngineState(),
            delegate: self
        )
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        syncEngine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        logger.debug("Initialized CKSyncEngine for Continuity")
        Task { await self.deleteLegacyQuerySubscription() }
    }

    private func fetchEngineChanges() async {
        guard let syncEngine else { return }
        do {
            try await syncEngine.fetchChanges()
        } catch {
            logger.error("CKSyncEngine fetchChanges failed: \(Self.describe(error), privacy: .public)")
        }
    }

    @discardableResult
    private func deleteLegacyQuerySubscription() async -> Bool {
        do {
            _ = try await resolvedDatabase().deleteSubscription(withID: Self.snapshotSubscriptionID)
            logger.debug("Deleted legacy UsageSnapshot query subscription")
            return true
        } catch {
            if Self.isUnknownItem(error) {
                return true
            }
            logger.error("Legacy subscription delete failed: \(Self.describe(error), privacy: .public)")
            return false
        }
    }

    private static func receipt(
        from record: CKRecord,
        expectedDevice: UsageSyncDevice
    ) throws -> ContinuityReceipt {
        guard let deviceRawValue = record[deviceKindKey] as? String,
              let device = UsageSyncDevice(rawValue: deviceRawValue),
              device == expectedDevice else {
            throw UsageSyncError.invalidRecord(
                recordName: record.recordID.recordName,
                reason: "unexpected device kind"
            )
        }
        guard let generation = record[syncGenerationKey] as? String, !generation.isEmpty else {
            throw UsageSyncError.invalidRecord(
                recordName: record.recordID.recordName,
                reason: "missing sync generation"
            )
        }
        guard let acknowledgedAt = record[acknowledgedAtKey] as? Date else {
            throw UsageSyncError.invalidRecord(
                recordName: record.recordID.recordName,
                reason: "missing acknowledgement date"
            )
        }
        return ContinuityReceipt(
            device: device,
            syncGeneration: generation,
            acknowledgedAt: acknowledgedAt
        )
    }

    private static func providerSnapshots(from record: CKRecord) throws -> [ProviderUsageSnapshot] {
        guard let payload = record[providerSnapshotsKey] as? Data else {
            return []
        }
        return try JSONDecoder().decode([ProviderUsageSnapshot].self, from: payload)
    }

    static func makeSnapshotRecordID() -> CKRecord.ID {
        CKRecord.ID(recordName: snapshotRecordName, zoneID: zoneID)
    }

    static func receiptRecordID(for device: UsageSyncDevice) -> CKRecord.ID {
        CKRecord.ID(recordName: "continuity-\(device.rawValue.lowercased())", zoneID: zoneID)
    }

    private func resolvedDatabase() -> any UsageSyncDatabase {
        if let injectedDatabase {
            return injectedDatabase
        }
        return ckDatabase()
    }

    private func ckDatabase() -> CKDatabase {
        if let cloudDatabase {
            return cloudDatabase
        }
        let container = CKContainer(identifier: containerIdentifier ?? Self.containerIdentifier)
        let database = container.privateCloudDatabase
        cloudDatabase = database
        return database
    }

    private static var isAppExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    private static func stateFileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetDataStorage.suiteName)?
            .appendingPathComponent(engineStateFilename)
    }

    private static func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let url = stateFileURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let url = Self.stateFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Could not persist CKSyncEngine state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func syncError(_ error: Error, recordName: String) -> UsageSyncError {
        if let syncError = error as? UsageSyncError {
            return syncError
        }
        return .recordOperationFailed(recordName: recordName, message: describe(error))
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        if let syncError = error as? UsageSyncError,
           case .recordOperationFailed(_, let message) = syncError {
            return message.contains("unknownItem") || message.contains("Unknown Item")
        }
        return (error as? CKError)?.code == .unknownItem
    }

    /// Render an error for logging, including concrete per-item partial failures.
    private static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }
        var parts = ["CKError.\(ckError.code) (\(ckError.errorCode)): \(ckError.localizedDescription)"]
        for (id, itemError) in ckError.partialErrorsByItemID ?? [:] {
            let itemCK = itemError as? CKError
            let code = itemCK.map { "CKError.\($0.code) (\($0.errorCode))" } ?? "\(itemError)"
            let name = (id as? CKRecord.ID)?.recordName ?? "\(id)"
            parts.append("item \(name): \(code)")
        }
        return parts.joined(separator: "; ")
    }
}

extension UsageSyncService: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            persistEngineState(event.stateSerialization)

        case .fetchedRecordZoneChanges(let event):
            for modification in event.modifications {
                lastKnownRecords[modification.record.recordID] = modification.record
            }
            for deletion in event.deletions {
                lastKnownRecords[deletion.recordID] = nil
            }

        case .fetchedDatabaseChanges(let event):
            for deletion in event.deletions where deletion.zoneID == Self.zoneID {
                lastKnownRecords.removeAll()
            }

        case .sentRecordZoneChanges(let event):
            handleSentRecordZoneChanges(event, syncEngine: syncEngine)

        case .accountChange, .sentDatabaseChanges,
             .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges,
             .didFetchChanges, .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let records = lastKnownRecords
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            if let record = records[recordID] {
                return record
            }
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) {
        for saved in event.savedRecords {
            lastKnownRecords[saved.recordID] = saved
        }

        var retryRecords: [CKSyncEngine.PendingRecordZoneChange] = []
        var retryZones: [CKSyncEngine.PendingDatabaseChange] = []

        for failed in event.failedRecordSaves {
            switch failed.error.code {
            case .serverRecordChanged:
                if let serverRecord = failed.error.serverRecord {
                    lastKnownRecords[serverRecord.recordID] = serverRecord
                }
                retryRecords.append(.saveRecord(failed.record.recordID))

            case .zoneNotFound:
                retryZones.append(.saveZone(CKRecordZone(zoneID: failed.record.recordID.zoneID)))
                retryRecords.append(.saveRecord(failed.record.recordID))

            case .unknownItem:
                lastKnownRecords[failed.record.recordID] = failed.record
                retryRecords.append(.saveRecord(failed.record.recordID))

            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .notAuthenticated, .operationCancelled:
                logger.debug(
                    "Retryable CKSyncEngine save error for \(failed.record.recordID.recordName, privacy: .public)"
                )

            default:
                sendFailure = Self.syncError(failed.error, recordName: failed.record.recordID.recordName)
            }
        }

        if !retryZones.isEmpty {
            syncEngine.state.add(pendingDatabaseChanges: retryZones)
        }
        if !retryRecords.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: retryRecords)
        }
    }
}
#endif
