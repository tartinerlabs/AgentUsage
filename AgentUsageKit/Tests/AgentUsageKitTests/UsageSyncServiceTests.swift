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

    @Test func codexExtraQuotasAndCreditBalanceRoundTrip() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let fetchedAt = Date()
        let codexSnapshot = ProviderUsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(
                    utilization: 22,
                    resetsAt: fetchedAt.addingTimeInterval(3_600),
                    windowType: .codexFiveHour
                ),
                UsageWindow(
                    utilization: 12,
                    resetsAt: fetchedAt.addingTimeInterval(86_400),
                    windowID: "codex.review.weekly",
                    displayName: "Code review weekly limit",
                    totalDuration: 604_800
                ),
                UsageWindow(
                    utilization: 40,
                    resetsAt: fetchedAt.addingTimeInterval(3_600),
                    windowID: "codex.model.codex_spark.five_hour",
                    displayName: "GPT-5.3-Codex-Spark 5-hour limit",
                    totalDuration: 18_000,
                    scope: UsageWindowScope(model: "GPT-5.3-Codex-Spark")
                ),
            ],
            planName: "Pro 20x",
            creditBalance: CreditBalance(remaining: 1_250),
            fetchedAt: fetchedAt
        )

        _ = try await service.publish(
            snapshot: nil,
            planType: "Free",
            providerSnapshots: [codexSnapshot]
        )
        let synced = try #require(await service.fetchLatest())
        let codex = try #require(synced.providerSnapshots.first)

        #expect(codex.windows.map(\.windowID.rawValue) == [
            "codexFiveHour",
            "codex.review.weekly",
            "codex.model.codex_spark.five_hour",
        ])
        #expect(codex.windows.map(\.windowType) == [.codexFiveHour, .custom, .custom])
        #expect(codex.windows.map(\.displayName) == [
            "5-hour limit",
            "Code review weekly limit",
            "GPT-5.3-Codex-Spark 5-hour limit",
        ])
        #expect(codex.windows.last?.scope?.model == "GPT-5.3-Codex-Spark")
        #expect(codex.creditBalance == CreditBalance(remaining: 1_250))
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
    }

    @Test func ensureSnapshotSubscriptionIsANoOpWithoutAnEngine() async throws {
        let service = UsageSyncService(database: StubUsageSyncDatabase())
        try await service.ensureSnapshotSubscription()
        try await service.ensureSnapshotSubscription()
    }

    @Test func mobileRevokeLeavesTheSharedSnapshot() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        let synced = SyncedUsageSnapshot(
            snapshot: Self.snapshot(),
            planType: "Pro",
            fetchedAt: Date(),
            syncGeneration: "generation-5"
        )
        _ = try await service.publish(snapshot: synced.snapshot, planType: "Pro")
        _ = try await service.acknowledge(snapshot: synced, from: .iPhone)

        #expect(await service.revoke(device: .iPhone))
        #expect(await database.record(named: "latest") != nil)
        #expect(await database.record(named: UsageSyncService.receiptRecordID(for: .iPhone).recordName) == nil)
    }

    @Test func deleteSnapshotSubscriptionTreatsMissingSubscriptionAsSuccess() async {
        let service = UsageSyncService(database: StubUsageSyncDatabase())

        #expect(await service.deleteSnapshotSubscription())
    }

    @Test func eachMacPublishesItsOwnLedger() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)

        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 4))
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-b", name: "MacBook", cost: 6))
        // Republishing replaces that Mac's ledger instead of adding another.
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 5))

        let ledgers = await service.fetchDeviceLedgers()

        #expect(ledgers.map(\.deviceID) == ["mac-a", "mac-b"])
        #expect(ledgers.map(\.deviceName) == ["Studio", "MacBook"])
        #expect(ledgers.first?.provider(.claude)?.today.costUSD == 5)
    }

    @Test func ledgersDoNotDisturbTheSharedSnapshot() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        _ = try await service.publish(snapshot: Self.snapshot(), planType: "Max")
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 1))

        let synced = try #require(await service.fetchLatest())
        let ledgers = await service.fetchDeviceLedgers()

        #expect(synced.planType == "Max")
        #expect(ledgers.map(\.deviceID) == ["mac-a"])
    }

    @Test func deleteDeviceLedgerRemovesOnlyThatMac() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 1))
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-b", name: "MacBook", cost: 2))

        #expect(await service.deleteDeviceLedger(deviceID: "mac-a"))

        #expect(await service.fetchDeviceLedgers().map(\.deviceID) == ["mac-b"])
    }

    @Test func macRevokeAlsoDeletesEveryLedger() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        _ = try await service.publish(snapshot: Self.snapshot(), planType: "Pro")
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 1))
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-b", name: "MacBook", cost: 2))

        #expect(await service.revokeAll())

        #expect(await service.fetchDeviceLedgers().isEmpty)
        #expect(await database.record(named: "latest") == nil)
    }

    @Test func undecodableLedgerIsSkipped() async throws {
        let database = StubUsageSyncDatabase()
        let service = UsageSyncService(database: database)
        try await service.publishDeviceLedger(Self.ledger(deviceID: "mac-a", name: "Studio", cost: 1))
        let broken = CKRecord(
            recordType: "DeviceUsageLedger",
            recordID: UsageSyncService.ledgerRecordID(for: "mac-z")
        )
        broken["payload"] = Data("not json".utf8) as CKRecordValue
        await database.seed(broken)

        #expect(await service.fetchDeviceLedgers().map(\.deviceID) == ["mac-a"])
    }

    @Test func ledgerWithoutEffortFieldsStillDecodes() throws {
        let json = """
        {"provider":"claude","today":{"tokens":{"input":1,"output":2,"cacheCreation":0,"cacheRead":0,\
        "reasoning":0,"cacheCreation1h":0},"costUSD":1.5},\
        "yesterday":{"tokens":{"input":0,"output":0,"cacheCreation":0,"cacheRead":0,"reasoning":0,\
        "cacheCreation1h":0},"costUSD":0},\
        "last30Days":{"tokens":{"input":1,"output":2,"cacheCreation":0,"cacheRead":0,"reasoning":0,\
        "cacheCreation1h":0},"costUSD":1.5},\
        "byModel":{},"dailyCosts":[1.5]}
        """

        let entry = try JSONDecoder().decode(ProviderLedger.self, from: Data(json.utf8))

        #expect(entry.hasTokenUsage)
        #expect(entry.effortSummaries.isEmpty)
        #expect(entry.lastUsedAt == nil)
        #expect(entry.today.costUSD == 1.5)
    }

    @Test func ledgerEffortRoundTrips() throws {
        let summary = EffortPeriodSummary(
            period: .last7Days,
            levels: [EffortLevelCount(level: .xhigh, sessionCount: 2)],
            classifiedSessionCount: 2,
            unclassifiedSessionCount: 1
        )
        let entry = ProviderLedger(
            provider: .codex,
            hasTokenUsage: false,
            today: .zero,
            yesterday: .zero,
            last30Days: .zero,
            byModel: [:],
            dailyCosts: [],
            effortSummaries: [summary],
            lastUsedAt: nil
        )

        let decoded = try JSONDecoder().decode(ProviderLedger.self, from: JSONEncoder().encode(entry))

        #expect(decoded == entry)
    }

    @Test func ledgerDayOffsetCountsCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 23)))

        #expect(DeviceUsageLedger.dayKey(for: date, calendar: calendar) == "2026-03-02")
        #expect(DeviceUsageLedger.dayOffset(from: "2026-03-02", to: date, calendar: calendar) == 0)
        #expect(DeviceUsageLedger.dayOffset(from: "2026-02-28", to: date, calendar: calendar) == 2)
        #expect(DeviceUsageLedger.dayOffset(from: "2026-03-03", to: date, calendar: calendar) == -1)
        #expect(DeviceUsageLedger.dayOffset(from: "garbage", to: date, calendar: calendar) == nil)
    }

    @Test func snapshotRecordLivesInTheContinuityZone() {
        #expect(UsageSyncService.makeSnapshotRecordID().zoneID == UsageSyncService.zoneID)
        #expect(UsageSyncService.receiptRecordID(for: .iPhone).zoneID == UsageSyncService.zoneID)
    }

    private static func ledger(deviceID: String, name: String, cost: Double) -> DeviceUsageLedger {
        let totals = LedgerTotals(tokens: LedgerTokens(input: 100, output: 50), costUSD: cost)
        return DeviceUsageLedger(
            deviceID: deviceID,
            deviceName: name,
            anchorDay: DeviceUsageLedger.dayKey(for: Date()),
            publishedAt: Date(),
            providers: [
                ProviderLedger(
                    provider: .claude,
                    today: totals,
                    yesterday: .zero,
                    last30Days: totals,
                    byModel: ["claude-opus": totals.tokens],
                    dailyCosts: [cost],
                    lastUsedAt: Date()
                ),
            ]
        )
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

    func seed(_ record: CKRecord) {
        recordsByName[record.recordID.recordName] = record
    }

    func failSave(recordName: String, code: CKError.Code) {
        saveFailures[recordName] = code
    }

    func omitSaveResult(recordName: String) {
        omittedSaveResults.insert(recordName)
    }

    func record(named name: String) -> CKRecord? {
        recordsByName[name]
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

    func deleteSubscription(withID _: CKSubscription.ID) async throws -> CKSubscription.ID {
        throw CKError(.unknownItem)
    }

    func allRecords(inZone zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        recordsByName.values.filter { $0.recordID.zoneID == zoneID }
    }
}
#endif
