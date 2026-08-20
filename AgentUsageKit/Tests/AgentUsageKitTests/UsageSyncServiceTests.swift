#if canImport(CloudKit)
@preconcurrency import CloudKit
import Foundation
import Testing
@testable import AgentUsageKit

@Suite("UsageSyncService")
struct UsageSyncServiceTests {
    @Test func publishReturnsGenerationAndStoresIt() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let snapshot = Self.snapshot()

        let publication = try await service.publish(snapshot: snapshot, planType: "Pro")
        let savedRecord = try #require(await database.record(named: "latest"))

        #expect(publication.syncGeneration.isEmpty == false)
        #expect(savedRecord["syncGeneration"] as? String == publication.syncGeneration)
        #expect(savedRecord["planType"] as? String == "Pro")
    }

    @Test func publishStoresProviderSnapshots() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let snapshot = Self.snapshot()
        let codexSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 42,
                    resetsAt: Date().addingTimeInterval(3600),
                    windowType: .codexFiveHour
                ),
            ],
            planName: "Plus",
            fetchedAt: snapshot.fetchedAt
        )

        _ = try await service.publish(
            snapshot: snapshot,
            planType: "Pro",
            providerSnapshots: [codexSnapshot]
        )
        let synced = try #require(await service.fetchLatest())

        #expect(synced.providerSnapshots.map(\.provider) == [.codex])
        #expect(synced.providerSnapshots.first?.planName == "Plus")
        #expect(synced.providerSnapshots.first?.windows.map(\.windowType) == [.codexFiveHour])
    }

    @Test func cursorSnapshotRoundTripsWithDynamicWindowsAndExtraUsage() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let fetchedAt = Date()
        let reset = fetchedAt.addingTimeInterval(31 * 24 * 3_600)
        let cursorSnapshot = ProviderUsageSnapshot(
            provider: .cursor,
            windows: [
                UsageWindow(
                    utilization: 37.5,
                    resetsAt: reset,
                    windowID: "cursor.total",
                    displayName: "Total usage",
                    totalDuration: 31 * 24 * 3_600
                ),
                UsageWindow(
                    utilization: 8,
                    resetsAt: reset,
                    windowID: "cursor.api",
                    displayName: "API usage",
                    totalDuration: 31 * 24 * 3_600
                ),
            ],
            extraUsage: ExtraUsageCost(used: 12, limit: 50, currencyCode: "USD"),
            planName: "Pro",
            fetchedAt: fetchedAt
        )

        _ = try await service.publish(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [cursorSnapshot]
        )
        let synced = try #require(await service.fetchLatest())
        let cursor = try #require(synced.providerSnapshots.first)

        #expect(cursor.provider == .cursor)
        #expect(cursor.windows.map(\.windowID.rawValue) == ["cursor.total", "cursor.api"])
        #expect(cursor.windows.map(\.windowType) == [.custom, .custom])
        #expect(cursor.windows.map(\.displayName) == ["Total usage", "API usage"])
        #expect(cursor.windows.allSatisfy { $0.totalDuration == 31 * 24 * 3_600 })
        #expect(cursor.extraUsage?.used == 12)
        #expect(cursor.extraUsage?.limit == 50)
        #expect(cursor.extraUsage?.currencyCode == "USD")
    }

    @Test func publishStoresProviderSnapshotsWithoutClaudeSnapshot() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let fetchedAt = Date()
        let codexSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 42,
                    resetsAt: Date().addingTimeInterval(3600),
                    windowType: .codexFiveHour
                ),
            ],
            planName: "Plus",
            fetchedAt: fetchedAt
        )

        let publication = try await service.publish(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [codexSnapshot]
        )
        let savedRecord = try #require(await database.record(named: "latest"))
        let synced = try #require(await service.fetchLatest())

        #expect(savedRecord["payload"] == nil)
        #expect(publication.fetchedAt == fetchedAt)
        #expect(synced.snapshot == nil)
        #expect(synced.providerSnapshots.map(\.provider) == [.codex])
    }

    @Test func publishSurfacesPerRecordFailure() async {
        let database = StubUsageSyncDatabase()
        await database.failSave(recordName: "latest", code: .serverRejectedRequest)
        let service = UsageSyncService(database: database)

        do {
            _ = try await service.publish(snapshot: Self.snapshot(), planType: "Pro")
            Issue.record("Expected the per-record save failure to be thrown")
        } catch let error as UsageSyncError {
            guard case .recordOperationFailed(let recordName, _) = error else {
                Issue.record("Unexpected sync error: \(error)")
                return
            }
            #expect(recordName == "latest")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func publishRejectsMissingPerRecordResult() async {
        let database = StubUsageSyncDatabase()
        await database.omitSaveResult(recordName: "latest")
        let service = UsageSyncService(database: database)

        await #expect(throws: UsageSyncError.missingRecordResult(recordName: "latest")) {
            _ = try await service.publish(snapshot: Self.snapshot(), planType: "Pro")
        }
    }

    @Test func legacySnapshotWithoutGenerationRemainsReadable() async throws {
        let database = StubUsageSyncDatabase()
        let snapshot = Self.snapshot()
        let record = CKRecord(recordType: "UsageSnapshot", recordID: CKRecord.ID(recordName: "latest"))
        record["payload"] = try JSONEncoder().encode(snapshot) as CKRecordValue
        record["planType"] = "Pro" as CKRecordValue
        record["fetchedAt"] = snapshot.fetchedAt as CKRecordValue
        await database.seed(record)

        let synced = await UsageSyncService(database: database).fetchLatest()

        #expect(synced?.planType == "Pro")
        #expect(synced?.providerSnapshots.isEmpty == true)
        #expect(synced?.syncGeneration == nil)
    }

    @Test func acknowledgementRoundTripsByDeviceFamily() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date(),
            syncGeneration: "generation-1"
        )

        let receipt = try await service.acknowledge(snapshot: synced, from: .iPhone)
        let receipts = try await service.fetchReceipts()

        #expect(receipt.device == .iPhone)
        #expect(receipts[.iPhone]?.syncGeneration == "generation-1")
        #expect(receipts[.iPad] == nil)
    }

    @Test func legacySnapshotCannotWriteReceipt() async {
        let service = UsageSyncService(database: StubUsageSyncDatabase())
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date()
        )

        await #expect(throws: UsageSyncError.missingSyncGeneration) {
            _ = try await service.acknowledge(snapshot: synced, from: .iPhone)
        }
    }

    @Test func acknowledgementSurfacesPerRecordFailure() async {
        let database = StubUsageSyncDatabase()
        let receiptID = UsageSyncService.receiptRecordID(for: .iPad)
        await database.failSave(recordName: receiptID.recordName, code: .serverRejectedRequest)
        let service = UsageSyncService(database: database)
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date(),
            syncGeneration: "generation-2"
        )

        do {
            _ = try await service.acknowledge(snapshot: synced, from: .iPad)
            Issue.record("Expected the receipt save failure to be thrown")
        } catch let error as UsageSyncError {
            guard case .recordOperationFailed(let recordName, _) = error else {
                Issue.record("Unexpected sync error: \(error)")
                return
            }
            #expect(recordName == receiptID.recordName)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func mobileRevokeDeletesOnlyItsReceipt() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date(),
            syncGeneration: "generation-3"
        )
        _ = try await service.publish(snapshot: synced.snapshot, planType: "Pro")
        _ = try await service.acknowledge(snapshot: synced, from: .iPhone)
        _ = try await service.acknowledge(snapshot: synced, from: .iPad)

        #expect(await service.revoke(device: .iPhone))

        #expect(await database.record(named: "latest") != nil)
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPhone).recordName) == nil)
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPad).recordName) != nil)
    }

    @Test func macRevokeDeletesSnapshotAndAllReceipts() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let snapshot = Self.snapshot()
        let synced = SyncedUsageSnapshot(
            snapshot: snapshot,
            planType: "Pro",
            fetchedAt: snapshot.fetchedAt,
            syncGeneration: "generation-4"
        )
        _ = try await service.publish(snapshot: snapshot, planType: "Pro")
        _ = try await service.acknowledge(snapshot: synced, from: .iPhone)
        _ = try await service.acknowledge(snapshot: synced, from: .iPad)

        #expect(await service.revokeAll())

        #expect(await database.record(named: "latest") == nil)
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPhone).recordName) == nil)
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPad).recordName) == nil)
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) == nil)
    }

    @Test func ensureSnapshotSubscriptionSavesContentAvailableQuery() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)

        try await service.ensureSnapshotSubscription()

        let saved = try #require(
            await database.subscription(id: UsageSyncService.snapshotSubscriptionID) as? CKQuerySubscription
        )
        #expect(saved.subscriptionID == UsageSyncService.snapshotSubscriptionID)
        #expect(saved.recordType == "UsageSnapshot")
        #expect(saved.notificationInfo?.shouldSendContentAvailable == true)
        #expect(saved.querySubscriptionOptions.contains(.firesOnRecordCreation))
        #expect(saved.querySubscriptionOptions.contains(.firesOnRecordUpdate))
        #expect(await database.saveSubscriptionCount() == 1)
    }

    @Test func ensureSnapshotSubscriptionIsIdempotentForDuplicateID() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.ensureSnapshotSubscription()
        try await service.ensureSnapshotSubscription()

        #expect(await database.saveSubscriptionCount() == 2)
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) != nil)
    }

    @Test func ensureSnapshotSubscriptionSurfacesNonDuplicateFailure() async {
        let database = StubUsageSyncDatabase()
        await database.failSaveSubscription(code: .networkFailure)
        let service = UsageSyncService(database: database)

        do {
            try await service.ensureSnapshotSubscription()
            Issue.record("Expected a non-duplicate subscription save failure to be thrown")
        } catch let error as UsageSyncError {
            guard case .recordOperationFailed(let recordName, _) = error else {
                Issue.record("Unexpected sync error: \(error)")
                return
            }
            #expect(recordName == UsageSyncService.snapshotSubscriptionID)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func macRevokeDeletesSilentPushSubscription() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.ensureSnapshotSubscription()

        #expect(await service.revokeAll())
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) == nil)
    }

    @Test func mobileRevokeKeepsSilentPushSubscription() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date(),
            syncGeneration: "generation-5"
        )
        _ = try await service.acknowledge(snapshot: synced, from: .iPhone)
        try await service.ensureSnapshotSubscription()

        #expect(await service.revoke(device: .iPhone))
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPhone).recordName) == nil)
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) != nil)
    }

    @Test func deleteSnapshotSubscriptionTreatsMissingSubscriptionAsSuccess() async {
        let service = UsageSyncService(database: StubUsageSyncDatabase())

        #expect(await service.deleteSnapshotSubscription())
    }

    @Test func ensureSnapshotSubscriptionRecreatesAfterRevoke() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.ensureSnapshotSubscription()
        #expect(await service.revokeAll())
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) == nil)
        #expect(await database.saveSubscriptionCount() == 1)

        try await service.ensureSnapshotSubscription()
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) != nil)
        #expect(await database.saveSubscriptionCount() == 2)
    }

    @Test func ensureSnapshotSubscriptionRecreatesAfterRemoteDelete() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.ensureSnapshotSubscription()
        await database.dropSubscription(id: UsageSyncService.snapshotSubscriptionID)
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) == nil)

        try await service.ensureSnapshotSubscription()
        #expect(await database.subscription(id: UsageSyncService.snapshotSubscriptionID) != nil)
        #expect(await database.saveSubscriptionCount() == 2)
    }

    private static func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            session: UsageWindow(
                utilization: 20,
                resetsAt: Date().addingTimeInterval(3600),
                windowType: .session
            ),
            opus: UsageWindow(
                utilization: 30,
                resetsAt: Date().addingTimeInterval(7200),
                windowType: .opus
            ),
            sonnet: nil,
            fetchedAt: Date()
        )
    }
}

private actor StubUsageSyncDatabase: UsageSyncDatabase {
    private var recordsByName: [String: CKRecord] = [:]
    private var saveFailures: [String: CKError.Code] = [:]
    private var omittedSaveResults: Set<String> = []
    private var subscriptionsByID: [CKSubscription.ID: CKSubscription] = [:]
    private var saveSubscriptionFailure: CKError.Code?
    private var savedSubscriptionCount = 0

    func seed(_ record: CKRecord) {
        recordsByName[record.recordID.recordName] = record
    }

    func failSave(recordName: String, code: CKError.Code) {
        saveFailures[recordName] = code
    }

    func omitSaveResult(recordName: String) {
        omittedSaveResults.insert(recordName)
    }

    func failSaveSubscription(code: CKError.Code) {
        saveSubscriptionFailure = code
    }

    func record(named name: String) -> CKRecord? {
        recordsByName[name]
    }

    func subscription(id: CKSubscription.ID) -> CKSubscription? {
        subscriptionsByID[id]
    }

    func saveSubscriptionCount() -> Int {
        savedSubscriptionCount
    }

    func dropSubscription(id: CKSubscription.ID) {
        subscriptionsByID.removeValue(forKey: id)
    }

    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        Dictionary(uniqueKeysWithValues: ids.map { id in
            if let record = recordsByName[id.recordName] {
                return (id, .success(record))
            }
            return (id, .failure(CKError(.unknownItem)))
        })
    }

    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, Error>],
        deleteResults: [CKRecord.ID: Result<Void, Error>]
    ) {
        var saveResults: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        for record in recordsToSave {
            let name = record.recordID.recordName
            guard !omittedSaveResults.contains(name) else { continue }
            if let code = saveFailures[name] {
                saveResults[record.recordID] = .failure(CKError(code))
            } else {
                recordsByName[name] = record
                saveResults[record.recordID] = .success(record)
            }
        }

        var deleteResults: [CKRecord.ID: Result<Void, Error>] = [:]
        for recordID in recordIDsToDelete {
            if recordsByName.removeValue(forKey: recordID.recordName) != nil {
                deleteResults[recordID] = .success(())
            } else {
                deleteResults[recordID] = .failure(CKError(.unknownItem))
            }
        }
        return (saveResults, deleteResults)
    }

    func saveSubscription(_ subscription: CKSubscription) async throws -> CKSubscription {
        savedSubscriptionCount += 1
        if let code = saveSubscriptionFailure {
            throw CKError(code)
        }
        if subscriptionsByID[subscription.subscriptionID] != nil {
            throw CKError(
                .serverRejectedRequest,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Error saving record subscription with id \(subscription.subscriptionID) to server: subscription is duplicate of '\(subscription.subscriptionID)'",
                ]
            )
        }
        subscriptionsByID[subscription.subscriptionID] = subscription
        return subscription
    }

    func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID {
        guard subscriptionsByID.removeValue(forKey: subscriptionID) != nil else {
            throw CKError(.unknownItem)
        }
        return subscriptionID
    }
}
#endif
