//
//  AgentUsageApp.swift
//  AgentUsage
//
//  Created by Ru Chern Chong on 31/12/25.
//

import SwiftUI
#if os(macOS)
import SwiftData
#endif

@main
struct AgentUsageApp: App {
    @State private var viewModel: UsageViewModel

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updaterController = UpdaterController()
    @AppStorage("selectedMainWindowTab") private var selectedTab: MainWindowTab = .dashboard
    @Environment(\.openWindow) private var openWindow

    let modelContainer: ModelContainer
    #else
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundRefreshCoordinator: BackgroundRefreshCoordinator
    #endif

    init() {
        #if os(macOS)
        // Resolve any user-granted folder bookmarks and begin holding their security
        // scope before any log-reading service runs, so reads under the sandbox succeed.
        _ = SandboxFolderAccessService.shared

        // Initialize SwiftData container
        let schema = Schema([
            TokenLogEntry.self,
            ImportedFile.self,
            DailyUsageRecordEntity.self,
            ProviderWindowDailyPeakEntity.self,
        ])
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

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
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
        if !Self.isRunningTests {
            coordinator.register()
        }
        #endif
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @SceneBuilder
    var body: some Scene {
        #if os(macOS)
        // Main window (opened from menu bar)
        Window(Constants.appDisplayName, id: Constants.mainWindowID) {
            MainWindowView()
                .environment(viewModel)
                .environmentObject(updaterController)
                .task {
                    await viewModel.initializeIfNeeded()
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    selectedTab = .settings
                    openWindow(id: Constants.mainWindowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Menu bar popover
        MenuBarExtra {
            MenuBarView()
                .environment(viewModel)
                .environmentObject(updaterController)
        } label: {
            MenuBarIconView()
                .environment(viewModel)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            MainTabView()
                .environment(viewModel)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        backgroundRefreshCoordinator.schedule()
                    }
                }
        }
        #endif
    }
}
