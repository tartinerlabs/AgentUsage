// Derived in part from steipete/CodexBar ProviderFetchPlan.swift.
// Upstream commit: 98de97833505a6213ec2cf3c2c6d528443b77d8d (MIT).

import AgentUsageKit
import Foundation

public enum ProviderRuntime: Sendable {
    case app
    case shadow
}

public enum ProviderSourceMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case oauth
    case api
    case cli
    case local
    case manualWeb
}

public enum ProviderFetchKind: String, Codable, Sendable {
    case oauth
    case api
    case cli
    case local
    case manualWeb

    public var defaultTimeout: Duration {
        switch self {
        case .local: .seconds(5)
        case .cli: .seconds(20)
        case .oauth, .api: .seconds(30)
        case .manualWeb: .seconds(60)
        }
    }
}

public struct ProviderFetchContext: Sendable {
    public let runtime: ProviderRuntime
    public let sourceMode: ProviderSourceMode
    public let environment: [String: String]

    public init(
        runtime: ProviderRuntime,
        sourceMode: ProviderSourceMode = .automatic,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runtime = runtime
        self.sourceMode = sourceMode
        self.environment = environment
    }
}

public struct ProviderFetchResult: Sendable {
    public let snapshot: ProviderUsageSnapshot
    public let sourceLabel: String
    public let strategyID: String
    public let strategyKind: ProviderFetchKind

    public init(
        snapshot: ProviderUsageSnapshot,
        sourceLabel: String,
        strategyID: String,
        strategyKind: ProviderFetchKind
    ) {
        self.snapshot = snapshot
        self.sourceLabel = sourceLabel
        self.strategyID = strategyID
        self.strategyKind = strategyKind
    }
}

public enum ProviderFailureCategory: String, Codable, Sendable {
    case unavailable
    case authentication
    case rateLimited
    case network
    case service
    case invalidResponse
    case timedOut
    case cancelled
    case unknown
}

public struct ProviderFetchAttempt: Codable, Sendable, Equatable {
    public let strategyID: String
    public let kind: ProviderFetchKind
    public let wasAvailable: Bool
    public let failureCategory: ProviderFailureCategory?

    public init(
        strategyID: String,
        kind: ProviderFetchKind,
        wasAvailable: Bool,
        failureCategory: ProviderFailureCategory?
    ) {
        self.strategyID = strategyID
        self.kind = kind
        self.wasAvailable = wasAvailable
        self.failureCategory = failureCategory
    }
}

public struct ProviderFetchFailure: Error, Sendable {
    public let category: ProviderFailureCategory

    public init(category: ProviderFailureCategory) {
        self.category = category
    }
}

public struct ProviderFetchOutcome: Sendable {
    public let result: Result<ProviderFetchResult, ProviderFetchFailure>
    public let attempts: [ProviderFetchAttempt]

    public init(
        result: Result<ProviderFetchResult, ProviderFetchFailure>,
        attempts: [ProviderFetchAttempt]
    ) {
        self.result = result
        self.attempts = attempts
    }
}

public protocol ProviderFetchStrategy: Sendable {
    var id: String { get }
    var kind: ProviderFetchKind { get }
    func isAvailable(in context: ProviderFetchContext) async -> Bool
    func fetch(in context: ProviderFetchContext) async throws -> ProviderFetchResult
    func shouldFallback(after error: Error, in context: ProviderFetchContext) -> Bool
    func classify(_ error: Error) -> ProviderFailureCategory
}

/// Type-erased strategy used by app-owned provider adapters. Keeping the
/// closures in ProviderCore lets applications adapt existing actors without
/// leaking credential types into the shared engine.
public struct AnyProviderFetchStrategy: ProviderFetchStrategy {
    public let id: String
    public let kind: ProviderFetchKind
    private let availability: @Sendable (ProviderFetchContext) async -> Bool
    private let operation: @Sendable (ProviderFetchContext) async throws -> ProviderFetchResult
    private let fallback: @Sendable (Error, ProviderFetchContext) -> Bool
    private let classification: @Sendable (Error) -> ProviderFailureCategory

    public init(
        id: String,
        kind: ProviderFetchKind,
        isAvailable: @escaping @Sendable (ProviderFetchContext) async -> Bool = { _ in true },
        fetch: @escaping @Sendable (ProviderFetchContext) async throws -> ProviderFetchResult,
        shouldFallback: @escaping @Sendable (Error, ProviderFetchContext) -> Bool = { _, context in
            context.sourceMode == .automatic
        },
        classify: @escaping @Sendable (Error) -> ProviderFailureCategory = Self.defaultClassification
    ) {
        self.id = id
        self.kind = kind
        self.availability = isAvailable
        self.operation = fetch
        self.fallback = shouldFallback
        self.classification = classify
    }

    public func isAvailable(in context: ProviderFetchContext) async -> Bool {
        await availability(context)
    }

    public func fetch(in context: ProviderFetchContext) async throws -> ProviderFetchResult {
        try await operation(context)
    }

    public func shouldFallback(after error: Error, in context: ProviderFetchContext) -> Bool {
        fallback(error, context)
    }

    public func classify(_ error: Error) -> ProviderFailureCategory { classification(error) }

    public static func defaultClassification(_ error: Error) -> ProviderFailureCategory {
        if error is CancellationError { return .cancelled }
        if let failure = error as? ProviderFetchFailure { return failure.category }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut { return .timedOut }
            if urlError.code == .cancelled { return .cancelled }
            return .network
        }
        return .unknown
    }
}

extension ProviderFetchStrategy {
    public func shouldFallback(after _: Error, in context: ProviderFetchContext) -> Bool {
        context.sourceMode == .automatic
    }

    public func classify(_ error: Error) -> ProviderFailureCategory {
        if error is CancellationError { return .cancelled }
        if let failure = error as? ProviderFetchFailure { return failure.category }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return .timedOut
            case .userAuthenticationRequired, .userCancelledAuthentication: return .authentication
            case .cancelled: return .cancelled
            default: return .network
            }
        }
        return .unknown
    }
}

public struct ProviderFetchPipeline: Sendable {
    public typealias StrategyResolver = @Sendable (ProviderFetchContext) async -> [any ProviderFetchStrategy]

    private let resolveStrategies: StrategyResolver

    public init(resolveStrategies: @escaping StrategyResolver) {
        self.resolveStrategies = resolveStrategies
    }

    public func fetch(
        provider: Provider,
        context: ProviderFetchContext
    ) async -> ProviderFetchOutcome {
        let strategies = await resolveStrategies(context)
        var attempts: [ProviderFetchAttempt] = []
        var lastFailure = ProviderFetchFailure(category: .unavailable)

        for strategy in strategies {
            guard !Task.isCancelled else {
                return .init(
                    result: .failure(.init(category: .cancelled)),
                    attempts: attempts
                )
            }

            let available = await strategy.isAvailable(in: context)
            guard available else {
                attempts.append(.init(
                    strategyID: strategy.id,
                    kind: strategy.kind,
                    wasAvailable: false,
                    failureCategory: nil
                ))
                continue
            }

            do {
                let result = try await withTimeout(strategy.kind.defaultTimeout) {
                    try await strategy.fetch(in: context)
                }
                guard result.snapshot.provider == provider else {
                    let failure = ProviderFetchFailure(category: .invalidResponse)
                    attempts.append(.init(
                        strategyID: strategy.id,
                        kind: strategy.kind,
                        wasAvailable: true,
                        failureCategory: failure.category
                    ))
                    return .init(result: .failure(failure), attempts: attempts)
                }
                attempts.append(.init(
                    strategyID: strategy.id,
                    kind: strategy.kind,
                    wasAvailable: true,
                    failureCategory: nil
                ))
                return .init(result: .success(result), attempts: attempts)
            } catch {
                let category: ProviderFailureCategory = error is ProviderTimeoutError
                    ? .timedOut
                    : strategy.classify(error)
                lastFailure = .init(category: category)
                attempts.append(.init(
                    strategyID: strategy.id,
                    kind: strategy.kind,
                    wasAvailable: true,
                    failureCategory: category
                ))
                if category == .cancelled || !strategy.shouldFallback(after: error, in: context) {
                    return .init(result: .failure(lastFailure), attempts: attempts)
                }
            }
        }

        return .init(result: .failure(lastFailure), attempts: attempts)
    }
}

public struct ProviderDescriptor: Sendable {
    public let provider: Provider
    public let displayName: String
    public let statusURL: URL?
    public let sourceModes: Set<ProviderSourceMode>
    public let pipeline: ProviderFetchPipeline

    public init(
        provider: Provider,
        displayName: String,
        statusURL: URL? = nil,
        sourceModes: Set<ProviderSourceMode>,
        pipeline: ProviderFetchPipeline
    ) {
        self.provider = provider
        self.displayName = displayName
        self.statusURL = statusURL
        self.sourceModes = sourceModes
        self.pipeline = pipeline
    }

    public func fetch(in context: ProviderFetchContext) async -> ProviderFetchOutcome {
        await pipeline.fetch(provider: provider, context: context)
    }
}

private struct ProviderTimeoutError: Error {}

private func withTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw ProviderTimeoutError()
        }
        guard let value = try await group.next() else { throw CancellationError() }
        group.cancelAll()
        return value
    }
}
