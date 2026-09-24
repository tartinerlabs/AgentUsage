//
//  DeviceUsage.swift
//  AgentUsage
//
//  Per-Mac local usage: which Macs to show, and how one Mac's ledger is built
//  from its `ProviderDetail`s and how several ledgers combine back into one.
//

import Foundation
import AgentUsageKit
#if os(macOS)
import SystemConfiguration
#endif

/// Which Macs' local token and cost usage the dashboards show. Quota windows
/// are account-wide and do not depend on this choice.
nonisolated enum UsageSourceSelection: Hashable, Sendable {
    case allMacs
    case mac(id: String)

    private static let macPrefix = "mac:"

    /// Parses the value stored in defaults.
    init?(rawValue: String) {
        if rawValue == "all" {
            self = .allMacs
        } else if rawValue.hasPrefix(Self.macPrefix) {
            let id = String(rawValue.dropFirst(Self.macPrefix.count))
            guard !id.isEmpty else { return nil }
            self = .mac(id: id)
        } else {
            return nil
        }
    }

    /// Stable string form for defaults and picker identity.
    var rawValue: String {
        switch self {
        case .allMacs: "all"
        case .mac(let id): Self.macPrefix + id
        }
    }
}

/// One entry in the usage source picker.
nonisolated struct UsageSourceOption: Identifiable, Hashable, Sendable {
    let selection: UsageSourceSelection
    let title: String
    var id: String { selection.rawValue }
}

/// Mac identity for the ledger this install publishes.
nonisolated enum LocalDeviceIdentity {
    static let deviceIDKey = "continuityDeviceID"

    /// Stable per-install identifier, created on first use.
    static func deviceID(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: deviceIDKey)
        return created
    }

    #if os(macOS)
    /// The computer name from System Settings › General › Sharing, read once per
    /// launch. `Host.current()` is avoided because it can block on DNS.
    static let deviceName: String = {
        let name = SCDynamicStoreCopyComputerName(nil, nil)
            .map { $0 as String }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return "Mac" }
        return name
    }()
    #endif
}

nonisolated enum DeviceUsageMerge {
    /// Days of daily cost carried per provider, matching `ProviderDetail.dailyCosts`.
    static let dailyCostDays = 30

    /// Build this Mac's ledger from its local provider details. Details that
    /// only carry effort metadata have no token usage to share and are left out.
    static func ledger(
        deviceID: String,
        deviceName: String,
        details: [Provider: ProviderDetail],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DeviceUsageLedger {
        let providers = details
            .filter { $0.value.hasTokenUsage }
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { provider, detail in
                ProviderLedger(
                    provider: provider,
                    today: LedgerTotals(detail.today),
                    yesterday: LedgerTotals(detail.yesterday),
                    last30Days: LedgerTotals(detail.last30Days),
                    byModel: detail.byModel.mapValues { LedgerTokens($0) },
                    dailyCosts: detail.dailyCosts,
                    lastUsedAt: detail.lastUsedAt
                )
            }
        return DeviceUsageLedger(
            deviceID: deviceID,
            deviceName: deviceName,
            anchorDay: DeviceUsageLedger.dayKey(for: now, calendar: calendar),
            publishedAt: now,
            providers: providers
        )
    }

    /// Combine one provider's usage across `ledgers` as of `now`.
    ///
    /// A ledger published on an earlier day is shifted: its "today" becomes
    /// "yesterday" a day later, and its daily costs move left. Its 30-day total
    /// and model split are kept until the ledger is 30 days old, so they can
    /// slightly overcount the oldest day. Nil when no ledger has the provider.
    static func detail(
        for provider: Provider,
        from ledgers: [DeviceUsageLedger],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProviderDetail? {
        var today = LedgerTotals.zero
        var yesterday = LedgerTotals.zero
        var last30Days = LedgerTotals.zero
        var byModel: [String: LedgerTokens] = [:]
        var dailyCosts = Array(repeating: 0.0, count: dailyCostDays)
        var lastUsedAt: Date?
        var found = false

        for ledger in ledgers {
            guard let entry = ledger.provider(provider),
                  let rawOffset = DeviceUsageLedger.dayOffset(
                      from: ledger.anchorDay,
                      to: now,
                      calendar: calendar
                  )
            else { continue }
            // A Mac in a time zone ahead of this device can publish "tomorrow".
            let offset = max(rawOffset, 0)
            guard offset < dailyCostDays else { continue }
            found = true

            if offset == 0 {
                today = today + entry.today
                yesterday = yesterday + entry.yesterday
            } else if offset == 1 {
                yesterday = yesterday + entry.today
            }
            last30Days = last30Days + entry.last30Days
            for (model, tokens) in entry.byModel {
                byModel[model] = (byModel[model] ?? .zero) + tokens
            }

            let count = entry.dailyCosts.count
            for (index, cost) in entry.dailyCosts.enumerated() {
                let daysAgo = (count - 1 - index) + offset
                let target = dailyCostDays - 1 - daysAgo
                if dailyCosts.indices.contains(target) {
                    dailyCosts[target] += cost
                }
            }

            if let used = entry.lastUsedAt {
                lastUsedAt = lastUsedAt.map { max($0, used) } ?? used
            }
        }

        guard found else { return nil }
        return ProviderDetail(
            today: today.summary(period: .today),
            yesterday: yesterday.summary(period: .today),
            last30Days: last30Days.summary(period: .last30Days),
            byModel: byModel.mapValues { TokenCount($0) },
            dailyCosts: dailyCosts,
            lastUsedAt: lastUsedAt
        )
    }
}

extension LedgerTokens {
    nonisolated init(_ tokens: TokenCount) {
        self.init(
            input: tokens.inputTokens,
            output: tokens.outputTokens,
            cacheCreation: tokens.cacheCreationTokens,
            cacheRead: tokens.cacheReadTokens,
            reasoning: tokens.reasoningTokens,
            cacheCreation1h: tokens.cacheCreation1hTokens
        )
    }
}

extension LedgerTotals {
    nonisolated init(_ summary: TokenUsageSummary) {
        self.init(tokens: LedgerTokens(summary.tokens), costUSD: summary.costUSD)
    }

    nonisolated func summary(period: UsagePeriod) -> TokenUsageSummary {
        TokenUsageSummary(tokens: TokenCount(tokens), costUSD: costUSD, period: period)
    }
}

extension TokenCount {
    nonisolated init(_ tokens: LedgerTokens) {
        self.init(
            inputTokens: tokens.input,
            outputTokens: tokens.output,
            cacheCreationTokens: tokens.cacheCreation,
            cacheReadTokens: tokens.cacheRead,
            reasoningTokens: tokens.reasoning,
            cacheCreation1hTokens: tokens.cacheCreation1h
        )
    }
}
