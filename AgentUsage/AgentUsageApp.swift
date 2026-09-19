//
//  AgentUsageApp.swift
//  AgentUsage
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI
#if os(macOS)
import OSLog
import SwiftData
#endif

@main
struct AgentUsageApp: App {
    @State private var viewModel: UsageViewModel

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Direct-distribution updater support is dormant while releases use App Store/TestFlight.
    // @StateObject private var updaterController = UpdaterController()
    @AppStorage("selectedMainWindowTab") private var selectedTab: NavigationTarget = .section(.dashboard)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var onboardingStore = OnboardingStore(platform: .mac)

    let modelContainer: ModelContainer
    #else
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundRefreshCoordinator: BackgroundRefreshCoordinator
    #endif

    init() {
        #if os(macOS)
        // Resolve any user-granted folder bookmarks and begin holding their security
        // scope before any log-reading service runs, so reads under the sandbox succeed.
        _ = SandboxFolderAccessService.shared

        // Initialize SwiftData container
        let schema = Schema(versionedSchema: TokenUsageSchemaV2.self)
        let modelConfiguration: ModelConfiguration
        if Self.isRunningTests {
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            // Pin the store to the App Group container explicitly. SwiftData otherwise
            // defaults into the group container only implicitly (because the app-groups
            // entitlement is present); making it explicit ensures the existing store is
            // never relocated/orphaned by entitlement changes.
            //
            // `cloudKitDatabase: .none` disables SwiftData's automatic iCloud mirroring.
            // The app now carries a CloudKit entitlement (for `UsageSyncService`), which
            // SwiftData would otherwise take as a cue to sync this store — failing at
            // launch because these @Model types have non-optional attributes without
            // defaults. This local token/history store must stay local; only
            // `UsageSyncService` uses CloudKit, via its own container and records.
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(Constants.appGroupIdentifier),
                cloudKitDatabase: .none
            )
        }

        // A corrupt store or a failed migration must not be an unrecoverable launch
        // crash: the persisted token/history data is a local cache rebuilt from the
        // CLI logs, so fall back to an in-memory store and let the app run degraded.
        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: TokenUsageMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            Logger.viewModel.error("Persistent ModelContainer unavailable, falling back to in-memory: \(error.localizedDescription)")
            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)]
                )
            } catch {
                fatalError("Could not initialize an in-memory ModelContainer: \(error)")
            }
        }

        // Use DependencyContainer for view model creation
        _viewModel = State(initialValue: DependencyContainer.createUsageViewModel(
            modelContext: modelContainer.mainContext
        ))
        #else
        let viewModel = DependencyContainer.createUsageViewModel()
        _viewModel = State(initialValue: viewModel)

        let coordinator = BackgroundRefreshCoordinator(
            scheduler: SystemBackgroundRefreshScheduler(),
            refresh: { await viewModel.refresh(force: true) },
            refreshFrequency: { viewModel.refreshInterval }
        )
        _backgroundRefreshCoordinator = State(initialValue: coordinator)
        // Silent CloudKit pushes can relaunch iOS without a scene. Wire the
        // view model at process start so `didReceiveRemoteNotification` can
        // refresh Live Activities without waiting for WindowGroup.onAppear.
        appDelegate.viewModel = viewModel
        if !Self.isRunningTests {
            coordinator.start()
        }
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    #if os(macOS)
    /// Show setup on a new install. Completion and skipping are persisted separately
    /// so dismissing the window does not silently mark setup as finished.
    private var shouldPresentOnboardingAtLaunch: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            return true
        }
        #endif
        guard !Self.isRunningTests else { return false }
        return onboardingStore.shouldPresent
    }
    #endif

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
        // Main window (opened from menu bar)
        Window(Constants.appDisplayName, id: Constants.mainWindowID) {
            MainNavigationView()
                .environment(viewModel)
                // .environmentObject(updaterController)
                .task {
                    // The unit-test host launches the full app; don't let it hit the real
                    // usage endpoint with the user's credentials on every test run.
                    guard !Self.isRunningTests else { return }
                    await viewModel.initializeIfNeeded()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    selectedTab = .section(.settings)
                    openWindow(id: Constants.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // First-run local data access setup. Presented at launch while pending
        // and reopened on demand from Settings via `.showOnboarding`.
        Window(Constants.appDisplayName, id: Constants.onboardingWindowID) {
            DataAccessOnboardingView(
                onComplete: {
                    onboardingStore.complete()
                    dismissWindow(id: Constants.onboardingWindowID)
                },
                onSkip: {
                    onboardingStore.skip()
                    dismissWindow(id: Constants.onboardingWindowID)
                }
            )
            .windowMinimizeBehavior(.disabled)
            .windowResizeBehavior(.disabled)
            .onAppear { onboardingStore.present() }
            // Closing with the window button must not count as finishing setup.
            .onDisappear { onboardingStore.dismissWithoutCompleting() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        // `.presented` is not honoured alongside a MenuBarExtra, so launch
        // presentation is driven explicitly from the menu bar label's task.
        .defaultLaunchBehavior(.suppressed)

        // Menu bar popover
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                // .environmentObject(updaterController)
        } label: {
            MenuBarIconView()
                .environment(viewModel)
                .task {
                    guard !Self.isRunningTests else { return }
                    await viewModel.initializeIfNeeded()
                }
                .task {
                    // Refresh immediately when the user grants local data access
                    // from the first-run onboarding, without waiting for the next cycle.
                    for await _ in NotificationCenter.default.notifications(named: .localDataAccessGranted) {
                        _ = await viewModel.refresh(force: true)
                    }
                }
                .task {
                    // Present first-run setup on launch, and again whenever
                    // "Run Setup Again" in Settings posts `.showOnboarding`.
                    if shouldPresentOnboardingAtLaunch {
                        openWindow(id: Constants.onboardingWindowID)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    for await _ in NotificationCenter.default.notifications(named: .showOnboarding) {
                        openWindow(id: Constants.onboardingWindowID)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            MainNavigationView()
                .environment(viewModel)
                .task {
                    await viewModel.handleScenePhase(scenePhase)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task { await viewModel.handleScenePhase(newPhase) }
                    if newPhase == .active {
                        Task {
                            await viewModel.refreshNotificationPermissionState()
                            await viewModel.refreshContinuitySync()
                        }
                    } else if newPhase == .background {
                        backgroundRefreshCoordinator.schedule()
                    }
                }
                .onChange(of: viewModel.refreshInterval) { _, _ in
                    // The pending request carries the old interval — and switching
                    // away from Manual has to submit one, since Manual cancels
                    // without re-submitting.
                    backgroundRefreshCoordinator.schedule()
                }
        }
        #endif
    }
}
