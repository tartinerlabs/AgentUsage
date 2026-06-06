//
//  CCUsageRunnerService.swift
//  ClaudeMeter
//

#if os(macOS)
import Foundation

actor CCUsageRunnerService {
    static let pinnedPackageVersion = "20.0.2"

    private static let commandTimeout: TimeInterval = 20
    private static let commonExecutableDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "~/.local/bin",
        "~/.nvm/current/bin"
    ]

    private let runnerCandidates: @Sendable () -> [RunnerCandidate]
    private let commandExecutor: @Sendable (CommandInvocation, TimeInterval) async throws -> CommandResult

    init() {
        self.runnerCandidates = {
            CCUsageRunnerService.defaultRunnerCandidates()
        }
        self.commandExecutor = { invocation, timeout in
            try await CCUsageRunnerService.runProcess(invocation: invocation, timeout: timeout)
        }
    }

    init(
        runnerCandidates: @escaping @Sendable () -> [RunnerCandidate],
        commandExecutor: @escaping @Sendable (CommandInvocation, TimeInterval) async throws -> CommandResult
    ) {
        self.runnerCandidates = runnerCandidates
        self.commandExecutor = commandExecutor
    }

    func fetchUsage() async throws -> CCUsageFetchResult {
        let since = Self.ccusageDateString(for: Self.lastYearStartDate())
        let timezone = TimeZone.current.identifier

        let report = try await runCCUsageJSON(since: since, timezone: timezone)
        return await MainActor.run {
            Self.mapReport(report)
        }
    }

    private func runCCUsageJSON(since: String, timezone: String) async throws -> (report: CCUsageDailyReport, runner: String) {
        let candidates = runnerCandidates()
        guard !candidates.isEmpty else {
            throw CCUsageRunnerError.noRunnerFound
        }

        var failures: [String] = []
        for candidate in candidates {
            let invocation = Self.makeInvocation(
                runner: candidate,
                since: since,
                timezone: timezone
            )

            do {
                let result = try await commandExecutor(invocation, Self.commandTimeout)
                guard result.exitCode == 0 else {
                    failures.append("\(candidate.displayName): \(result.stderr)")
                    continue
                }

                guard let data = result.stdout.data(using: .utf8) else {
                    failures.append("\(candidate.displayName): stdout was not UTF-8")
                    continue
                }

                do {
                    let report = try JSONDecoder().decode(CCUsageDailyReport.self, from: data)
                    return (report, candidate.displayName)
                } catch {
                    failures.append("\(candidate.displayName): invalid JSON \(error.localizedDescription)")
                }
            } catch {
                failures.append("\(candidate.displayName): \(error.localizedDescription)")
            }
        }

        throw CCUsageRunnerError.allRunnersFailed(failures)
    }
}

extension CCUsageRunnerService {
    struct RunnerCandidate: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case pnx
            case pnpx
            case pnpmDlx
        }

        let kind: Kind
        let executableURL: URL

        var displayName: String {
            switch kind {
            case .pnx: return "pnx"
            case .pnpx: return "pnpx"
            case .pnpmDlx: return "pnpm dlx"
            }
        }

        var baseArguments: [String] {
            switch kind {
            case .pnx, .pnpx:
                return ["ccusage@\(CCUsageRunnerService.pinnedPackageVersion)"]
            case .pnpmDlx:
                return ["dlx", "ccusage@\(CCUsageRunnerService.pinnedPackageVersion)"]
            }
        }
    }

    struct CommandInvocation: Sendable, Equatable {
        let runner: RunnerCandidate
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    struct CommandResult: Sendable, Equatable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    struct CCUsageFetchResult: Sendable {
        let snapshot: TokenUsageSnapshot
        let periodSummaries: [UsagePeriod: TokenUsageSummary]
    }
}

enum CCUsageRunnerError: Error, LocalizedError, Equatable {
    case noRunnerFound
    case allRunnersFailed([String])
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .noRunnerFound:
            return "No pnpm v11 runner found. Install pnpm v11 so ClaudeMeter can run pnx, pnpx, or pnpm dlx."
        case .allRunnersFailed(let failures):
            return "ccusage failed with all runners: \(failures.joined(separator: "; "))"
        case .timedOut(let runner):
            return "ccusage timed out while running with \(runner)."
        }
    }
}

extension CCUsageRunnerService {
    static func defaultRunnerCandidates(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [RunnerCandidate] {
        var candidates: [RunnerCandidate] = []
        if let url = findExecutable(named: "pnx", environment: environment) {
            candidates.append(RunnerCandidate(kind: .pnx, executableURL: url))
        }
        if let url = findExecutable(named: "pnpx", environment: environment) {
            candidates.append(RunnerCandidate(kind: .pnpx, executableURL: url))
        }
        if let url = findExecutable(named: "pnpm", environment: environment) {
            candidates.append(RunnerCandidate(kind: .pnpmDlx, executableURL: url))
        }
        return candidates
    }

    static func makeInvocation(
        runner: RunnerCandidate,
        since: String,
        timezone: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CommandInvocation {
        let arguments = runner.baseArguments + [
            "daily",
            "--json",
            "--since",
            since,
            "--order",
            "desc",
            "--timezone",
            timezone
        ]

        return CommandInvocation(
            runner: runner,
            executableURL: runner.executableURL,
            arguments: arguments,
            environment: enrichedEnvironment(environment)
        )
    }

    static func findExecutable(
        named name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        var directories = commonExecutableDirectories.map(expandTilde)
        if let path = environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        var seen = Set<String>()
        for directory in directories {
            guard !directory.isEmpty, seen.insert(directory).inserted else { continue }
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func enrichedEnvironment(_ environment: [String: String]) -> [String: String] {
        var next = environment
        let pathEntries = commonExecutableDirectories.map(expandTilde)
        let existingPath = environment["PATH"] ?? ""
        next["PATH"] = (pathEntries + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        return next
    }

    private static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" {
            return home
        }
        return home + String(path.dropFirst())
    }

    private static func ccusageDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func lastYearStartDate() -> Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    }
}

extension CCUsageRunnerService {
    private static func runProcess(
        invocation: CommandInvocation,
        timeout: TimeInterval
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.environment = invocation.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let completionState = ProcessCompletionState()

            let finish: @Sendable (Result<CommandResult, Error>) -> Void = { result in
                guard completionState.markCompleted() else { return }
                continuation.resume(with: result)
            }

            process.terminationHandler = { process in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                finish(.success(CommandResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )))
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                process.terminate()
                finish(.failure(CCUsageRunnerError.timedOut(invocation.runner.displayName)))
            }
        }
    }
}

private nonisolated final class ProcessCompletionState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasCompleted = false

    func markCompleted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return false }
        hasCompleted = true
        return true
    }
}

private nonisolated struct CCUsageDailyReport: Decodable {
    let daily: [CCUsageDailyEntry]
    let totals: CCUsageTotals?
}

private nonisolated struct CCUsageDailyEntry: Decodable {
    let agent: String?
    let period: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double?
    let modelBreakdowns: [CCUsageModelBreakdown]?
    let metadata: CCUsageMetadata?

    var tokens: TokenCount {
        TokenCount(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}

private nonisolated struct CCUsageTotals: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let totalCost: Double?

    var tokens: TokenCount {
        TokenCount(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}

private nonisolated struct CCUsageModelBreakdown: Decodable {
    let modelName: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let cost: Double?

    var tokens: TokenCount {
        TokenCount(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }
}

private nonisolated struct CCUsageMetadata: Decodable {
    let agents: [String]?
}

extension CCUsageRunnerService {
    @MainActor
    private static func mapReport(_ input: (report: CCUsageDailyReport, runner: String)) -> CCUsageFetchResult {
        let report = input.report
        let runner = input.runner
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        let todayEntries = report.daily.filter { entry in
            guard let date = parsePeriodDate(entry.period) else { return false }
            return calendar.isDate(date, inSameDayAs: todayStart)
        }

        let today = summary(entries: todayEntries, period: .today)
        var periodSummaries: [UsagePeriod: TokenUsageSummary] = [:]
        for period in UsagePeriod.allCases {
            periodSummaries[period] = summary(
                entries: entries(in: period, from: report.daily),
                period: period
            )
        }

        let snapshot = TokenUsageSnapshot(
            today: today,
            last30Days: periodSummaries[.last30Days] ?? summary(entries: report.daily, period: .last30Days),
            byModel: aggregateModels(report.daily),
            fetchedAt: now,
            detectedProviders: detectedProviders(report.daily),
            providerBreakdown: providerBreakdown(report.daily),
            dataSource: .ccusage(runner: runner)
        )

        return CCUsageFetchResult(snapshot: snapshot, periodSummaries: periodSummaries)
    }

    @MainActor
    private static func entries(in period: UsagePeriod, from entries: [CCUsageDailyEntry]) -> [CCUsageDailyEntry] {
        let startDate = period.startDate
        return entries.filter { entry in
            guard let date = parsePeriodDate(entry.period) else { return false }
            return date >= startDate
        }
    }

    @MainActor
    private static func summary(entries: [CCUsageDailyEntry], period: UsagePeriod) -> TokenUsageSummary {
        var tokens = TokenCount.zero
        var costUSD = 0.0
        for entry in entries {
            tokens = tokens + entry.tokens
            costUSD += entry.totalCost ?? 0
        }
        return TokenUsageSummary(tokens: tokens, costUSD: costUSD, period: period)
    }

    @MainActor
    private static func aggregateModels(_ entries: [CCUsageDailyEntry]) -> [String: TokenCount] {
        var byModel: [String: TokenCount] = [:]
        for entry in entries {
            for model in entry.modelBreakdowns ?? [] {
                let existing = byModel[model.modelName] ?? .zero
                byModel[model.modelName] = existing + model.tokens
            }
        }
        return byModel
    }

    @MainActor
    private static func detectedProviders(_ entries: [CCUsageDailyEntry]) -> [UsageProvider] {
        var ids = Set<String>()
        for entry in entries {
            if let agent = entry.agent, agent != "all" {
                ids.insert(agent)
            }
            for agent in entry.metadata?.agents ?? [] {
                ids.insert(agent)
            }
        }
        return ids.sorted().map { UsageProvider(id: $0) }
    }

    @MainActor
    private static func providerBreakdown(_ entries: [CCUsageDailyEntry]) -> [ProviderUsageSummary] {
        var tokensByProvider: [String: TokenCount] = [:]
        var costByProvider: [String: Double] = [:]
        var modelsByProvider: [String: [String: TokenCount]] = [:]

        for entry in entries {
            guard let agent = entry.agent, agent != "all" else { continue }
            tokensByProvider[agent] = (tokensByProvider[agent] ?? .zero) + entry.tokens
            costByProvider[agent, default: 0] += entry.totalCost ?? 0

            var models = modelsByProvider[agent] ?? [:]
            for model in entry.modelBreakdowns ?? [] {
                models[model.modelName] = (models[model.modelName] ?? .zero) + model.tokens
            }
            modelsByProvider[agent] = models
        }

        return tokensByProvider.keys.sorted().map { agent in
            ProviderUsageSummary(
                provider: UsageProvider(id: agent),
                tokens: tokensByProvider[agent] ?? .zero,
                costUSD: costByProvider[agent] ?? 0,
                byModel: modelsByProvider[agent] ?? [:]
            )
        }
    }

    private static func parsePeriodDate(_ period: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: period)
    }
}
#endif
