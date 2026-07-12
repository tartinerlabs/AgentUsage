//
//  BackgroundRefreshCoordinator.swift
//  AgentUsage
//

import Foundation
import OSLog

@MainActor
protocol BackgroundRefreshTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

@MainActor
protocol BackgroundRefreshScheduling: AnyObject {
    @discardableResult
    func register(
        identifier: String,
        handler: @escaping (any BackgroundRefreshTask) -> Void
    ) -> Bool
    func submit(identifier: String, earliestBeginDate: Date) throws
    func cancel(identifier: String)
}

@MainActor
final class BackgroundRefreshCoordinator {
    static let taskIdentifier = "com.tartinerlabs.AgentUsage.refresh"
    static let minimumInterval: TimeInterval = 15 * 60

    private let scheduler: any BackgroundRefreshScheduling
    private let refresh: () async -> ClaudeRefreshOutcome
    private let refreshFrequency: () -> RefreshFrequency
    private let now: () -> Date
    private let logger = Logger(
        subsystem: "com.tartinerlabs.AgentUsage",
        category: "BackgroundRefresh"
    )
    private var activeWork: Task<Void, Never>?

    init(
        scheduler: any BackgroundRefreshScheduling,
        refresh: @escaping () async -> ClaudeRefreshOutcome,
        refreshFrequency: @escaping () -> RefreshFrequency,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.refresh = refresh
        self.refreshFrequency = refreshFrequency
        self.now = now
    }

    @discardableResult
    func register() -> Bool {
        scheduler.register(identifier: Self.taskIdentifier) { [weak self] task in
            self?.handle(task)
        }
    }

    func schedule() {
        scheduler.cancel(identifier: Self.taskIdentifier)

        let frequency = refreshFrequency()
        guard let requestedInterval = frequency.timeInterval else {
            logger.debug("Background refresh disabled for manual mode")
            return
        }

        let interval = max(requestedInterval, Self.minimumInterval)
        do {
            try scheduler.submit(
                identifier: Self.taskIdentifier,
                earliestBeginDate: now().addingTimeInterval(interval)
            )
            logger.debug("Submitted background refresh request")
        } catch {
            logger.error("Failed to submit background refresh: \(error.localizedDescription)")
        }
    }

    private func handle(_ task: any BackgroundRefreshTask) {
        schedule()

        let completion = BackgroundRefreshCompletion(task: task)
        let work = Task { @MainActor [weak self, completion] in
            guard let self else {
                completion.finish(success: false)
                return
            }
            let outcome = await refresh()
            completion.finish(success: !Task.isCancelled && outcome.completedSuccessfully)
            activeWork = nil
        }
        activeWork = work

        task.expirationHandler = { [weak self, weak completion] in
            Task { @MainActor in
                self?.activeWork?.cancel()
                self?.activeWork = nil
                completion?.finish(success: false)
            }
        }
    }
}

@MainActor
private final class BackgroundRefreshCompletion {
    private let task: any BackgroundRefreshTask
    private var hasFinished = false

    init(task: any BackgroundRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        guard !hasFinished else { return }
        hasFinished = true
        task.setTaskCompleted(success: success)
    }
}

#if os(iOS)
import BackgroundTasks

@MainActor
final class SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling {
    func register(
        identifier: String,
        handler: @escaping (any BackgroundRefreshTask) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handler(SystemBackgroundRefreshTask(task: task))
            }
        }
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

@MainActor
private final class SystemBackgroundRefreshTask: BackgroundRefreshTask {
    private let task: BGAppRefreshTask

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    var expirationHandler: (() -> Void)? {
        get { task.expirationHandler }
        set { task.expirationHandler = newValue }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
#endif
