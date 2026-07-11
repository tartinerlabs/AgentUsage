//
//  TokenUsageCoordinator.swift
//  AgentUsage
//

#if os(macOS)
import Foundation
import AgentUsageKit
import SwiftData

struct TokenUsageRefreshUpdate {
    let snapshot: TokenUsageSnapshot
    /// Empty for the direct-service fallback, which leaves the existing period cache unchanged.
    let periodSummaries: [UsagePeriod: TokenUsageSummary]
    let selectedPeriodSummary: TokenUsageSummary?
}

@MainActor
protocol TokenUsageCoordinating {
    func refresh(selectedPeriod: UsagePeriod) async throws -> TokenUsageRefreshUpdate
    func summary(for period: UsagePeriod) async throws -> TokenUsageSummary
    func providerDetails(using snapshot: TokenUsageSnapshot?) async -> [Provider: ProviderDetail]
}

/// Coordinates local-log imports and SwiftData queries without owning observable UI state.
@MainActor
final class TokenUsageCoordinator: TokenUsageCoordinating {
    static let costModelRepricedVersionKey = "costModelRepricedVersion"
    static let lastCleanupDateKey = "lastTokenCleanupDate"
    static let lastZeroCostRecalcDateKey = "lastZeroCostRecalcDate"
    static let costModelVersion = 3

    private let tokenService: (any TokenUsageServiceProtocol)?
    private let tokenRepository: TokenUsageRepository?
    private let tokenQuerier: TokenUsageQuerier?
    private let defaults: UserDefaults
    private let now: () -> Date

    init(
        tokenService: (any TokenUsageServiceProtocol)?,
        modelContext: ModelContext? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() }
    ) {
        self.tokenService = tokenService
        self.tokenRepository = modelContext.map { TokenUsageRepository(modelContext: $0) }
        self.tokenQuerier = modelContext.map { TokenUsageQuerier(modelContainer: $0.container) }
        self.defaults = defaults
        self.now = now
    }

    func refresh(selectedPeriod: UsagePeriod) async throws -> TokenUsageRefreshUpdate {
        if let tokenRepository, let tokenService {
            return try await refreshPersistedUsage(
                repository: tokenRepository,
                service: tokenService,
                selectedPeriod: selectedPeriod
            )
        }

        guard let tokenService else {
            throw TokenUsageError.repositoryUnavailable
        }

        do {
            return TokenUsageRefreshUpdate(
                snapshot: try await tokenService.fetchUsage(),
                periodSummaries: [:],
                selectedPeriodSummary: nil
            )
        } catch {
            throw TokenUsageError.fileReadError(error)
        }
    }

    func summary(for period: UsagePeriod) async throws -> TokenUsageSummary {
        if let tokenQuerier {
            return try await tokenQuerier.fetchSummary(for: period)
        }
        if let tokenRepository {
            return try await tokenRepository.fetchSummary(for: period)
        }
        throw TokenUsageError.repositoryUnavailable
    }

    func providerDetails(using snapshot: TokenUsageSnapshot?) async -> [Provider: ProviderDetail] {
        var details: [Provider: ProviderDetail] = [:]

        if let tokenService {
            let currentDate = now()
            let since = Calendar.current.date(byAdding: .day, value: -30, to: currentDate) ?? currentDate
            details = await tokenService.fetchExtraProviderDetails(since: since)
        }

        if let snapshot {
            let points = (try? await tokenQuerier?.fetchDailyTokenPoints(days: 30)) ?? []
            let yesterdayPoint = points.count >= 2 ? points[points.count - 2] : nil
            details[.claude] = ProviderDetail(
                today: snapshot.today,
                yesterday: TokenUsageSummary(
                    tokens: TokenCount(
                        inputTokens: yesterdayPoint?.tokens ?? 0,
                        outputTokens: 0,
                        cacheCreationTokens: 0,
                        cacheReadTokens: 0
                    ),
                    costUSD: yesterdayPoint?.costUSD ?? 0,
                    period: .today
                ),
                last30Days: snapshot.last30Days,
                byModel: snapshot.byModel,
                dailyCosts: points.map(\.costUSD)
            )
        }

        return details
    }

    private func refreshPersistedUsage(
        repository: TokenUsageRepository,
        service: any TokenUsageServiceProtocol,
        selectedPeriod: UsagePeriod
    ) async throws -> TokenUsageRefreshUpdate {
        let fileStates: [String: TokenUsageService.FileState]
        do {
            fileStates = try repository.getAllFileStates()
        } catch {
            throw TokenUsageError.swiftDataError(error)
        }

        let parsedResults: [URL: TokenUsageService.IncrementalParseResult]
        do {
            parsedResults = try await service.fetchParsedEntries(fileStates: fileStates)
        } catch {
            throw TokenUsageError.fileReadError(error)
        }

        for (fileURL, result) in parsedResults {
            do {
                try await repository.importEntries(
                    result.entries,
                    forFile: fileURL,
                    newByteOffset: result.newByteOffset,
                    newFileSize: result.newFileSize,
                    newModified: result.newModified
                )
            } catch {
                throw TokenUsageError.swiftDataError(error)
            }
        }

        await performMaintenance(repository: repository)

        let snapshot: TokenUsageSnapshot
        do {
            if let tokenQuerier {
                snapshot = try await tokenQuerier.fetchSnapshot()
            } else {
                snapshot = try await repository.fetchSnapshot()
            }
        } catch {
            throw TokenUsageError.swiftDataError(error)
        }

        var summaries: [UsagePeriod: TokenUsageSummary] = [
            .today: snapshot.today,
            .last30Days: snapshot.last30Days,
        ]
        let selectedSummary: TokenUsageSummary?
        if selectedPeriod == .today {
            selectedSummary = snapshot.today
        } else if selectedPeriod == .last30Days {
            selectedSummary = snapshot.last30Days
        } else {
            selectedSummary = try? await summary(for: selectedPeriod)
            if let selectedSummary {
                summaries[selectedPeriod] = selectedSummary
            }
        }

        return TokenUsageRefreshUpdate(
            snapshot: snapshot,
            periodSummaries: summaries,
            selectedPeriodSummary: selectedSummary
        )
    }

    private func performMaintenance(repository: TokenUsageRepository) async {
        if shouldRunMaintenance(key: Self.lastCleanupDateKey) {
            try? await repository.cleanupOldEntries()
            defaults.set(now().timeIntervalSince1970, forKey: Self.lastCleanupDateKey)
        }

        if shouldRunMaintenance(key: Self.lastZeroCostRecalcDateKey) {
            _ = try? await repository.recalculateZeroCostEntries()
            defaults.set(now().timeIntervalSince1970, forKey: Self.lastZeroCostRecalcDateKey)
        }

        if defaults.integer(forKey: Self.costModelRepricedVersionKey) < Self.costModelVersion {
            _ = try? await repository.recalculateAllCosts()
            defaults.set(Self.costModelVersion, forKey: Self.costModelRepricedVersionKey)
        }
    }

    private func shouldRunMaintenance(key: String) -> Bool {
        let lastRun = defaults.double(forKey: key)
        guard lastRun > 0 else { return true }
        return now().timeIntervalSince1970 - lastRun >= 24 * 60 * 60
    }
}
#endif
