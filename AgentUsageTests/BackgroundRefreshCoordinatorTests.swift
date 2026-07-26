//
//  BackgroundRefreshCoordinatorTests.swift
//  AgentUsageTests
//

import Foundation
import Testing
@testable import AgentUsage

@Suite("BackgroundRefreshCoordinator")
struct BackgroundRefreshCoordinatorTests {
    @Test @MainActor func registersAndClampsSchedulingToFifteenMinutes() throws {
        let scheduler = MockBackgroundRefreshScheduler()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var frequency = RefreshFrequency.oneMinute
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            refresh: { .updated },
            refreshFrequency: { frequency },
            now: { now }
        )

        #expect(coordinator.register())
        #expect(scheduler.registeredIdentifier == BackgroundRefreshCoordinator.taskIdentifier)

        coordinator.schedule()

        #expect(scheduler.cancelledIdentifiers == [BackgroundRefreshCoordinator.taskIdentifier])
        #expect(scheduler.submissions.count == 1)
        #expect(
            scheduler.submissions.first?.earliestBeginDate
                == now.addingTimeInterval(BackgroundRefreshCoordinator.minimumInterval)
        )

        frequency = .manual
        coordinator.schedule()

        #expect(scheduler.cancelledIdentifiers.count == 2)
        #expect(scheduler.submissions.count == 1)
    }

    @Test @MainActor func launchReschedulesAndCompletesSuccessfulRefresh() async {
        let scheduler = MockBackgroundRefreshScheduler()
        var refreshCount = 0
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            refresh: {
                refreshCount += 1
                return .updated
            },
            refreshFrequency: { .fifteenMinutes }
        )
        coordinator.register()
        let task = MockBackgroundRefreshTask()

        scheduler.launch(task)
        await waitForCompletion(task)

        #expect(refreshCount == 1)
        #expect(scheduler.submissions.count == 1)
        #expect(task.completions == [true])
    }

    /// A completed attempt is a successful task regardless of what the refresh
    /// found. iOS uses the success flag to decide how willingly to wake the app
    /// again, and "the Mac published nothing new" must not count against us.
    @Test(arguments: [
        ClaudeRefreshOutcome.updated,
        .noUsageData,
        .failed,
        .skipped,
    ])
    @MainActor
    func reportsCompletedAttemptAsSuccessForEveryOutcome(outcome: ClaudeRefreshOutcome) async {
        let scheduler = MockBackgroundRefreshScheduler()
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            refresh: { outcome },
            refreshFrequency: { .fifteenMinutes }
        )
        coordinator.register()
        let task = MockBackgroundRefreshTask()

        scheduler.launch(task)
        await waitForCompletion(task)

        #expect(task.completions == [true])
    }

    @Test @MainActor func startRegistersAndSubmitsAnInitialRequest() {
        let scheduler = MockBackgroundRefreshScheduler()
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            refresh: { .updated },
            refreshFrequency: { .fifteenMinutes },
            now: { now }
        )

        #expect(coordinator.start())

        // Without this, an app that never reaches `.background` cleanly leaves no
        // pending request and iOS has nothing to wake.
        #expect(scheduler.registeredIdentifier == BackgroundRefreshCoordinator.taskIdentifier)
        #expect(scheduler.submissions.count == 1)
        #expect(
            scheduler.submissions.first?.earliestBeginDate
                == now.addingTimeInterval(BackgroundRefreshCoordinator.minimumInterval)
        )
    }

    @Test @MainActor func expirationCancelsAndCompletesExactlyOnce() async {
        let scheduler = MockBackgroundRefreshScheduler()
        let coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            refresh: {
                try? await Task.sleep(for: .seconds(30))
                return .updated
            },
            refreshFrequency: { .fifteenMinutes }
        )
        coordinator.register()
        let task = MockBackgroundRefreshTask()

        scheduler.launch(task)
        task.expirationHandler?()
        await waitForCompletion(task)
        for _ in 0..<3 { await Task.yield() }

        #expect(task.completions == [false])
    }

    @MainActor
    private func waitForCompletion(_ task: MockBackgroundRefreshTask) async {
        for _ in 0..<50 where task.completions.isEmpty {
            await Task.yield()
        }
    }
}

@MainActor
private final class MockBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    struct Submission {
        let identifier: String
        let earliestBeginDate: Date
    }

    var registeredIdentifier: String?
    var cancelledIdentifiers: [String] = []
    var submissions: [Submission] = []
    private var handler: ((any BackgroundRefreshTask) -> Void)?

    func register(
        identifier: String,
        handler: @escaping (any BackgroundRefreshTask) -> Void
    ) -> Bool {
        registeredIdentifier = identifier
        self.handler = handler
        return true
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        submissions.append(Submission(identifier: identifier, earliestBeginDate: earliestBeginDate))
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    func launch(_ task: any BackgroundRefreshTask) {
        handler?(task)
    }
}

@MainActor
private final class MockBackgroundRefreshTask: BackgroundRefreshTask {
    var expirationHandler: (() -> Void)?
    var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
        completions.append(success)
    }
}
