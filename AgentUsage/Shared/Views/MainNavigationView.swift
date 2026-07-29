//
//  MainNavigationView.swift
//  AgentUsage
//
//  The app's single top-level navigation container. A `sidebarAdaptable`
//  `TabView` resolves itself per platform — bottom tab bar on iPhone, adaptable
//  top bar/sidebar on iPad, sidebar on Mac — so iOS and macOS share one
//  structure instead of a tab bar plus a hand-rolled NavigationSplitView.
//
//  Providers are first-class destinations, but how they're exposed depends on
//  how much room the platform gives them, because the provider list is expected
//  to grow well past today's handful:
//
//  - Where a sidebar exists (Mac, regular-width iPad) each provider is its own
//    row under a "Providers" section. Sidebars scroll, so this holds up at any
//    provider count and keeps every provider one click away.
//  - In compact width (iPhone) a single "Providers" tab holds a list that pushes
//    to the same detail view. The tab bar therefore stays at four tabs no matter
//    how many providers exist — stuffing providers into the tab bar itself would
//    break as soon as more than a couple were connected.
//
//  `Tab(value:)`, `TabSection`, and `.sidebarAdaptable` all ship in iOS 18 /
//  macOS 15, so the structure runs at the current deployment targets. Only the
//  Liquid Glass tab-bar behaviours are iOS 26, and those sit behind an
//  availability check in `LiquidGlassTabBarBehaviour`.
//

import AgentUsageKit
import SwiftUI

// MARK: - Destinations

/// A fixed top-level destination, present on every platform.
///
/// Raw values persist in `UserDefaults` under `selectedMainWindowTab`; renaming
/// one silently resets the tab people last had open.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    /// The compact-width stand-in for the sidebar's per-provider rows.
    case providers
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .providers: "Providers"
        case .settings: "Settings"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            #if os(macOS)
            return "gauge.with.dots.needle.bottom.50percent"
            #else
            return "chart.bar"
            #endif
        case .providers:
            return "square.stack.3d.up"
        case .settings:
            #if os(macOS)
            return "slider.horizontal.3"
            #else
            return "gear"
            #endif
        case .about:
            return "info.circle"
        }
    }
}

/// Everything the top-level navigation can select: a fixed section, or one
/// provider's usage detail.
///
/// String-backed so `@AppStorage` can persist it, and so the values written by
/// earlier builds ("dashboard", "settings", "about") still decode.
enum NavigationTarget: Hashable, RawRepresentable {
    case section(AppSection)
    case provider(Provider)

    private static let providerPrefix = "provider."

    init?(rawValue: String) {
        if let section = AppSection(rawValue: rawValue) {
            self = .section(section)
            return
        }
        guard rawValue.hasPrefix(Self.providerPrefix),
              let provider = Provider(rawValue: String(rawValue.dropFirst(Self.providerPrefix.count)))
        else {
            return nil
        }
        self = .provider(provider)
    }

    var rawValue: String {
        switch self {
        case .section(let section): section.rawValue
        case .provider(let provider): Self.providerPrefix + provider.rawValue
        }
    }
}

// MARK: - Container

struct MainNavigationView: View {
    @Environment(UsageViewModel.self) private var viewModel
    @AppStorage("selectedMainWindowTab") private var selection: NavigationTarget = .section(.dashboard)

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var onboardingStore = OnboardingStore(platform: .mobile)
    #endif

    /// Whether there's a sidebar to list providers in. When there isn't, they
    /// live behind the single `.providers` tab instead.
    private var showsProvidersInSidebar: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    /// `TabView` needs a selection that always matches a visible tab, and which
    /// tabs exist varies with width and platform. Resolving on read rather than
    /// rewriting `selection` means a provider stays selected in storage while the
    /// window is narrow, and comes back when it widens again.
    private var tabSelection: Binding<NavigationTarget> {
        Binding(
            get: {
                switch selection {
                case .provider(_) where !showsProvidersInSidebar:
                    return .section(.providers)
                case .section(.providers) where showsProvidersInSidebar:
                    return .section(.dashboard)
                default:
                    return selection
                }
            },
            set: { selection = $0 }
        )
    }

    var body: some View {
        platformContainer
            .onChange(of: viewModel.availableProviders) { _, providers in
                // A provider's data can go away between refreshes. Without this the
                // selection would point at a tab that no longer exists, leaving the
                // content area blank.
                if case .provider(let provider) = selection, !providers.contains(provider) {
                    selection = .section(.dashboard)
                }
            }
    }

    /// Platform chrome that wraps the shared tab structure: window sizing on the
    /// Mac, brand tint and first-run onboarding on iOS.
    @ViewBuilder
    private var platformContainer: some View {
        #if os(macOS)
        tabView
            .frame(minWidth: 760, idealWidth: 920, minHeight: 560, idealHeight: 680)
        #else
        tabView
            .tint(Constants.brandPrimary)
            .onAppear {
                presentOnboardingIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
                onboardingStore.present()
            }
            .fullScreenCover(isPresented: onboardingPresentation) {
                ContinuityOnboardingView(
                    onComplete: { onboardingStore.complete() },
                    onSkip: { onboardingStore.skip() }
                )
                .environment(viewModel)
            }
        #endif
    }

    private var tabView: some View {
        TabView(selection: tabSelection) {
            Tab(
                AppSection.dashboard.title,
                systemImage: AppSection.dashboard.systemImage,
                value: NavigationTarget.section(.dashboard)
            ) {
                NavigationStack {
                    dashboardContent
                }
            }

            // The Wrapped destination is intentionally absent: `ClaudeWrappedView`
            // is still driven entirely by `WrappedSummary.mock`, so shipping it
            // would show every user a fabricated year. Restore it once the
            // CloudKit sync core (GitHub #8) supplies real yearly totals.

            if showsProvidersInSidebar {
                TabSection(AppSection.providers.title) {
                    ForEach(viewModel.availableProviders) { provider in
                        Tab(
                            provider.displayName,
                            systemImage: provider.iconName,
                            value: NavigationTarget.provider(provider)
                        ) {
                            NavigationStack {
                                ProviderSectionView(provider: provider)
                            }
                        }
                    }
                }
            } else {
                Tab(
                    AppSection.providers.title,
                    systemImage: AppSection.providers.systemImage,
                    value: NavigationTarget.section(.providers)
                ) {
                    NavigationStack {
                        ProviderListView()
                    }
                }
            }

            Tab(
                AppSection.settings.title,
                systemImage: AppSection.settings.systemImage,
                value: NavigationTarget.section(.settings)
            ) {
                NavigationStack {
                    settingsContent
                }
            }

            Tab(
                AppSection.about.title,
                systemImage: AppSection.about.systemImage,
                value: NavigationTarget.section(.about)
            ) {
                NavigationStack {
                    aboutContent
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .modifier(LiquidGlassTabBarBehaviour())
    }

    // MARK: Section content
    //
    // The structure is shared; the leaves stay platform-specific because the Mac
    // window and the phone present the same data at very different densities.

    @ViewBuilder
    private var dashboardContent: some View {
        #if os(macOS)
        DashboardTabView()
            .navigationTitle(AppSection.dashboard.title)
        #else
        DashboardView()
        #endif
    }

    @ViewBuilder
    private var settingsContent: some View {
        #if os(macOS)
        SettingsTabView()
            .navigationTitle(AppSection.settings.title)
        #else
        SettingsView()
        #endif
    }

    @ViewBuilder
    private var aboutContent: some View {
        #if os(macOS)
        AboutTabView()
            .navigationTitle(AppSection.about.title)
        #else
        AboutView()
        #endif
    }

    // MARK: Onboarding

    #if os(iOS)
    private func presentOnboardingIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            onboardingStore.present()
        } else {
            onboardingStore.presentIfNeeded()
        }
        #else
        onboardingStore.presentIfNeeded()
        #endif
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { onboardingStore.isPresented },
            set: { isPresented in
                if !isPresented {
                    onboardingStore.dismissWithoutCompleting()
                }
            }
        )
    }
    #endif
}

// MARK: - Liquid Glass behaviours

/// The iOS 26 tab-bar behaviours: the bar minimizes as content scrolls away, and
/// a persistent status pill rides above it. A no-op on older systems, which keep
/// the standard bar.
///
/// Deliberately iOS-only. The Mac equivalent would be a sidebar footer, which
/// both looks wrong under a sidebar and duplicates what the dashboard header and
/// the menu bar popover already show.
private struct LiquidGlassTabBarBehaviour: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    UsageStatusAccessory()
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if os(iOS)
/// Persistent status pill: overall usage pressure, how fresh the numbers are,
/// and a refresh affordance — visible whichever destination is showing.
///
/// Deliberately one line, so it reads the same in the collapsed inline placement
/// as in the expanded one.
@available(iOS 26, *)
private struct UsageStatusAccessory: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 16)

            Text(viewModel.overallStatus.label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(viewModel.overallStatus.color)
                .lineLimit(1)

            if let relativeText = viewModel.timeSinceLastUpdate {
                LastUpdatedLabel(
                    relativeText: relativeText,
                    isCached: viewModel.isUsingCachedData,
                    isOffline: viewModel.isOffline,
                    neutralStyle: AnyShapeStyle(.secondary)
                )
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.refresh(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel("Refresh usage")
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if viewModel.isLoading {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: viewModel.overallStatus.icon)
                .foregroundStyle(viewModel.overallStatus.color)
        }
    }
}
#endif

// MARK: - Provider destinations

/// The compact-width providers destination: every provider in one scrollable list
/// that pushes to the same detail the sidebar shows directly. This is what keeps
/// the iPhone tab bar at a fixed four tabs as providers are added.
///
/// Intentionally not searchable. Filtering a handful of provider names doesn't
/// earn a search field, and a search affordance here would imply it searches
/// usage data, which it wouldn't.
private struct ProviderListView: View {
    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        List {
            ForEach(viewModel.availableProviders) { provider in
                NavigationLink(value: provider) {
                    ProviderRow(provider: provider, usage: viewModel.usageSnapshot(for: provider))
                }
            }
        }
        .navigationTitle(AppSection.providers.title)
        .navigationDestination(for: Provider.self) { provider in
            ProviderSectionView(provider: provider)
        }
        .overlay {
            if viewModel.availableProviders.isEmpty {
                ContentUnavailableView(
                    "No Providers Yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Providers appear here once usage has been recorded for them.")
                )
            }
        }
    }
}

private struct ProviderRow: View {
    let provider: Provider
    let usage: ProviderUsageSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(provider.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                if let planName = usage?.planName {
                    Text(planName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One provider's usage: a sidebar destination on Mac and regular-width iPad, a
/// pushed detail from `ProviderListView` on iPhone.
struct ProviderSectionView: View {
    let provider: Provider

    @Environment(UsageViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            // Reset countdowns are minute-granularity, so a periodic timeline is
            // enough to keep them honest — and it keeps Combine out of this file,
            // which the module's mixed `internal import Combine` would otherwise
            // make ambiguous.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ProviderCardView(
                    provider: provider,
                    planName: usage?.planName,
                    windows: usage?.windows ?? [],
                    extraUsage: usage?.extraUsage,
                    now: context.date,
                    showExtraUsage: viewModel.showExtraUsageIndicators,
                    isServiceDown: viewModel.isServiceDown(provider),
                    rateLimitResetCredits: usage?.rateLimitResetCredits
                )
            }
            .frame(maxWidth: 760)
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle(provider.displayName)
    }

    private var usage: ProviderUsageSnapshot? {
        viewModel.usageSnapshot(for: provider)
    }
}
