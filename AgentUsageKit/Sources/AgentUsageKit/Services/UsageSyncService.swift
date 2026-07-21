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
}

extension CKDatabase: UsageSyncDatabase {}

/// Publishes and reads the latest usage snapshot through the user's private
/// CloudKit database. Reads remain best-effort so callers can use cached data;
/// writes throw when either the batch or the target record fails.
public actor UsageSyncService: UsageSyncServicing {
    public static let shared = UsageSyncService()

    /// CloudKit container. Must match the iCloud container entitlement on every target.
    public static let containerIdentifier = "iCloud.com.tartinerlabs.AgentUsage"

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

    private var database: (any UsageSyncDatabase)?
    private let containerIdentifier: String?
    private let snapshotRecordID: CKRecord.ID
    private let logger = Logger(subsystem: "com.tartinerlabs.AgentUsage", category: "UsageSync")

    public init(containerIdentifier: String = UsageSyncService.containerIdentifier) {
        self.database = nil
        self.containerIdentifier = containerIdentifier
        self.snapshotRecordID = CKRecord.ID(recordName: Self.snapshotRecordName)
    }

    init(database: any UsageSyncDatabase) {
        self.database = database
        self.containerIdentifier = nil
        self.snapshotRecordID = CKRecord.ID(recordName: Self.snapshotRecordName)
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
            let providersPayload = try JSONEncoder().encode(providerSnapshots)
            let record = CKRecord(recordType: Self.snapshotRecordType, recordID: snapshotRecordID)
            if let snapshot {
                record[Self.payloadKey] = try JSONEncoder().encode(snapshot) as CKRecordValue
            }
            record[Self.planTypeKey] = planType as CKRecordValue
            record[Self.providerSnapshotsKey] = providersPayload as CKRecordValue
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
        do {
            let database = resolvedDatabase()
            let results = try await database.records(for: [snapshotRecordID], desiredKeys: nil)
            guard let result = results[snapshotRecordID] else {
                throw UsageSyncError.missingRecordResult(recordName: snapshotRecordID.recordName)
            }
            let record = try result.get()

            let snapshot: UsageSnapshot?
            if let payload = record[Self.payloadKey] as? Data {
                snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: payload)
            } else {
                snapshot = nil
            }
            let providerSnapshots = try Self.providerSnapshots(from: record)
            guard snapshot != nil || !providerSnapshots.isEmpty else {
                throw UsageSyncError.invalidRecord(
                    recordName: snapshotRecordID.recordName,
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
        let record = CKRecord(recordType: Self.receiptRecordType, recordID: recordID)
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
        let recordIDs = UsageSyncDevice.allCases.map(Self.receiptRecordID(for:))

        do {
            let database = resolvedDatabase()
            let results = try await database.records(for: recordIDs, desiredKeys: nil)
            var receipts: [UsageSyncDevice: ContinuityReceipt] = [:]

            for device in UsageSyncDevice.allCases {
                let recordID = Self.receiptRecordID(for: device)
                guard let result = results[recordID] else {
                    throw UsageSyncError.missingRecordResult(recordName: recordID.recordName)
                }

                do {
                    receipts[device] = try Self.receipt(from: result.get(), expectedDevice: device)
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

    /// Remove the shared snapshot and all device receipts. Used by macOS when
    /// Continuity Sync is revoked for the whole shared setup.
    public func revokeAll() async -> Bool {
        await delete(
            recordIDs: [snapshotRecordID] + UsageSyncDevice.allCases.map(Self.receiptRecordID(for:))
        )
    }

    /// Remove only one mobile device's acknowledgement. Other devices and the
    /// Mac-published snapshot remain available.
    public func revoke(device: UsageSyncDevice) async -> Bool {
        await delete(recordIDs: [Self.receiptRecordID(for: device)])
    }

    /// Backward-compatible whole-setup revoke for existing callers.
    @discardableResult
    public func revoke() async -> Bool {
        await revokeAll()
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
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
        return try recordResult.get()
    }

    private func delete(recordIDs: [CKRecord.ID]) async -> Bool {
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

    static func receiptRecordID(for device: UsageSyncDevice) -> CKRecord.ID {
        CKRecord.ID(recordName: "continuity-\(device.rawValue.lowercased())")
    }

    private func resolvedDatabase() -> any UsageSyncDatabase {
        if let database {
            return database
        }
        let container = CKContainer(identifier: containerIdentifier ?? Self.containerIdentifier)
        let database = container.privateCloudDatabase
        self.database = database
        return database
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
#endif
