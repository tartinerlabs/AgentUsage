// Generation and coalescing semantics adapted from steipete/CodexBar.
// Upstream commit: 98de97833505a6213ec2cf3c2c6d528443b77d8d (MIT).

import AgentUsageKit
import Foundation

public enum ProviderFreshness: String, Codable, Sendable {
    case fresh
    case stale
    case expired
    case unavailable
}

public struct ProviderRuntimeState: Codable, Sendable {
    public let provider: Provider
    public let snapshot: ProviderUsageSnapshot?
    public let sourceLabel: String?
    public let freshness: ProviderFreshness
    public let failureCategory: ProviderFailureCategory?
    public let attempts: [ProviderFetchAttempt]
    public let generation: UInt64
    public let lastSuccessfulAt: Date?

    public init(
        provider: Provider,
        snapshot: ProviderUsageSnapshot? = nil,
        sourceLabel: String? = nil,
        freshness: ProviderFreshness = .unavailable,
        failureCategory: ProviderFailureCategory? = nil,
        attempts: [ProviderFetchAttempt] = [],
        generation: UInt64 = 0,
        lastSuccessfulAt: Date? = nil
    ) {
        self.provider = provider
        self.snapshot = snapshot
        self.sourceLabel = sourceLabel
        self.freshness = freshness
        self.failureCategory = failureCategory
        self.attempts = attempts
        self.generation = generation
        self.lastSuccessfulAt = lastSuccessfulAt
    }

    public func evaluated(at now: Date) -> ProviderRuntimeState {
        guard let snapshot else { return self }
        let activeWindows = snapshot.windows.filter { !$0.isExpired(from: now) }
        let evaluatedFreshness: ProviderFreshness = activeWindows.isEmpty ? .expired : freshness
        return .init(
            provider: provider,
            snapshot: snapshot,
            sourceLabel: sourceLabel,
            freshness: evaluatedFreshness,
            failureCategory: failureCategory,
            attempts: attempts,
            generation: generation,
            lastSuccessfulAt: lastSuccessfulAt
        )
    }
}

public enum ProviderRefreshPolicy: Sendable {
    case coalesce
    case replace
}

public actor ProviderEngine {
    public typealias StateObserver = @Sendable ([Provider: ProviderRuntimeState]) async -> Void

    private let descriptors: [Provider: ProviderDescriptor]
    private let observer: StateObserver?
    private var states: [Provider: ProviderRuntimeState]
    private var generations: [Provider: UInt64] = [:]
    private var tasks: [Provider: Task<Void, Never>] = [:]

    public init(
        descriptors: [ProviderDescriptor],
        restoredStates: [Provider: ProviderRuntimeState] = [:],
        observer: StateObserver? = nil
    ) {
        self.descriptors = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.provider, $0) })
        self.states = restoredStates
        self.observer = observer
    }

    public func currentStates(at now: Date = Date()) -> [Provider: ProviderRuntimeState] {
        states.mapValues { $0.evaluated(at: now) }
    }

    public func refresh(
        providers: Set<Provider>,
        context: ProviderFetchContext,
        policy: ProviderRefreshPolicy
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { [weak self] in
                    await self?.refresh(provider: provider, context: context, policy: policy)
                }
            }
        }
    }

    public func refresh(
        provider: Provider,
        context: ProviderFetchContext,
        policy: ProviderRefreshPolicy
    ) async {
        if policy == .coalesce, let existing = tasks[provider] {
            await existing.value
            return
        }

        if policy == .replace {
            tasks[provider]?.cancel()
        }

        let generation = (generations[provider] ?? 0) &+ 1
        generations[provider] = generation
        let descriptor = descriptors[provider]
        let task = Task { [weak self] in
            guard let self else { return }
            guard let descriptor else {
                await self.applyFailure(
                    provider: provider,
                    generation: generation,
                    category: .unavailable,
                    attempts: []
                )
                return
            }
            let outcome = await descriptor.fetch(in: context)
            guard !Task.isCancelled else { return }
            await self.apply(
                provider: provider,
                generation: generation,
                outcome: outcome
            )
        }
        tasks[provider] = task
        await task.value
        if generations[provider] == generation {
            tasks[provider] = nil
        }
    }

    private func apply(
        provider: Provider,
        generation: UInt64,
        outcome: ProviderFetchOutcome
    ) async {
        guard generations[provider] == generation else { return }
        switch outcome.result {
        case .success(let result):
            states[provider] = .init(
                provider: provider,
                snapshot: result.snapshot,
                sourceLabel: result.sourceLabel,
                freshness: .fresh,
                failureCategory: nil,
                attempts: outcome.attempts,
                generation: generation,
                lastSuccessfulAt: result.snapshot.fetchedAt
            ).evaluated(at: Date())
        case .failure(let failure):
            await applyFailure(
                provider: provider,
                generation: generation,
                category: failure.category,
                attempts: outcome.attempts
            )
            return
        }
        await observer?(currentStates())
    }

    private func applyFailure(
        provider: Provider,
        generation: UInt64,
        category: ProviderFailureCategory,
        attempts: [ProviderFetchAttempt]
    ) async {
        guard generations[provider] == generation else { return }
        let previous = states[provider]
        states[provider] = .init(
            provider: provider,
            snapshot: previous?.snapshot,
            sourceLabel: previous?.sourceLabel,
            freshness: previous?.snapshot == nil ? .unavailable : .stale,
            failureCategory: category,
            attempts: attempts,
            generation: generation,
            lastSuccessfulAt: previous?.lastSuccessfulAt
        ).evaluated(at: Date())
        await observer?(currentStates())
    }
}
