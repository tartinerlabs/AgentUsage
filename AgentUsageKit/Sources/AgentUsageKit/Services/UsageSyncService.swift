//
//  UsageSyncService.swift
//  AgentUsageKit
//
//  Cross-device usage sync via CloudKit.
//
//  macOS is the single source of truth: it fetches usage from the provider
//  endpoints and `publish`es the resulting `UsageSnapshot` to the user's private
//  CloudKit database. iOS and the widgets `fetchLatest` from there instead of
//  calling the Claude API themselves, so the account is polled once (by the Mac)
//  rather than once per device + per widget.
//
//  A single record (`recordName == "latest"`) is overwritten on each publish; we
//  don't need history here, only the most recent snapshot.
//

#if canImport(CloudKit)
import CloudKit
import Foundation
import OSLog

/// A usage snapshot received from another device via CloudKit, tagged with the
/// time the source device fetched it.
public struct SyncedUsageSnapshot: Sendable {
    public let snapshot: UsageSnapshot
    public let planType: String
    /// When the *source* device fetched this from the provider (not when it synced).
    public let fetchedAt: Date

    public init(snapshot: UsageSnapshot, planType: String, fetchedAt: Date) {
        self.snapshot = snapshot
        self.planType = planType
        self.fetchedAt = fetchedAt
    }

    /// Seconds since the source device fetched this snapshot.
    public func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}

/// Publishes and reads the latest usage snapshot through the user's private
/// CloudKit database. Best-effort: every operation degrades to a no-op / `nil`
/// when iCloud is unavailable, so callers can fall back to a direct fetch.
public actor UsageSyncService {
    public static let shared = UsageSyncService()

    /// CloudKit container. Must match the `com.apple.developer.icloud-container-identifiers`
    /// entitlement on the macOS and iOS app targets.
    public static let containerIdentifier = "iCloud.com.tartinerlabs.AgentUsage"

    private static let recordType = "UsageSnapshot"
    private static let recordName = "latest"
    private static let payloadKey = "payload"
    private static let planTypeKey = "planType"
    private static let fetchedAtKey = "fetchedAt"

    private let database: CKDatabase
    private let recordID: CKRecord.ID
    private let logger = Logger(subsystem: "com.tartinerlabs.AgentUsage", category: "UsageSync")

    public init(containerIdentifier: String = UsageSyncService.containerIdentifier) {
        let container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.recordID = CKRecord.ID(recordName: UsageSyncService.recordName)
    }

    /// Publish the latest snapshot, overwriting the previous one. Called by the
    /// macOS app after a successful fetch. Failures are logged and swallowed.
    public func publish(snapshot: UsageSnapshot, planType: String) async {
        do {
            let payload = try JSONEncoder().encode(snapshot)
            let record = CKRecord(recordType: Self.recordType, recordID: recordID)
            record[Self.payloadKey] = payload as CKRecordValue
            record[Self.planTypeKey] = planType as CKRecordValue
            record[Self.fetchedAtKey] = snapshot.fetchedAt as CKRecordValue

            // `.allKeys` overwrites the existing record regardless of change tag —
            // we always want the newest snapshot to win.
            _ = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: true
            )
            logger.debug("Published usage snapshot to CloudKit")
        } catch {
            logger.error("CloudKit publish failed: \(Self.describe(error), privacy: .public)")
        }
    }

    /// Fetch the most recently published snapshot, or `nil` when none exists yet
    /// or iCloud is unavailable. Never throws — callers fall back to a direct fetch.
    public func fetchLatest() async -> SyncedUsageSnapshot? {
        do {
            let results = try await database.records(for: [recordID])
            guard let result = results[recordID] else { return nil }
            let record = try result.get()

            guard let payload = record[Self.payloadKey] as? Data else {
                logger.error("CloudKit snapshot record missing payload")
                return nil
            }
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: payload)
            let planType = record[Self.planTypeKey] as? String ?? "Free"
            let fetchedAt = record[Self.fetchedAtKey] as? Date ?? snapshot.fetchedAt
            return SyncedUsageSnapshot(snapshot: snapshot, planType: planType, fetchedAt: fetchedAt)
        } catch {
            // A missing record (never published yet) is the expected empty state, so
            // keep it at debug. Anything else — missing record type (schema not
            // deployed to Production), auth, quota, server rejection — is a real
            // failure worth surfacing in `log stream` / Console.
            if (error as? CKError)?.code == .unknownItem {
                logger.debug("CloudKit fetch: no snapshot published yet")
            } else {
                logger.error("CloudKit fetch failed: \(Self.describe(error), privacy: .public)")
            }
            return nil
        }
    }

    /// Renders an error for logging, pulling out the concrete `CKError` code (and any
    /// per-item partial-failure codes) so a swallowed sync failure is diagnosable.
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
