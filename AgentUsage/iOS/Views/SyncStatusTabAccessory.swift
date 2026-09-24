//
//  SyncStatusTabAccessory.swift
//  AgentUsage
//
//  The iOS 26 tab-bar accessory: Continuity Sync freshness plus a refresh
//  control, laid out like Music's mini player (what's happening on the left, the
//  one control you reach for on the right).
//
//  iOS never fetches provider usage itself — every number on screen is whatever
//  the Mac last published over CloudKit — so how old that snapshot is decides
//  whether anything else can be trusted. It therefore sits on every tab. It stays
//  neutral while sync is healthy and turns orange only when the data is stale,
//  the device is offline, or there's no Mac to sync from.
//

#if os(iOS)
import AgentUsageKit
import SwiftUI

/// What the accessory is saying. Derived from `appConnectionStatus`, the network,
/// and snapshot age so it reuses the Settings wording rather than inventing more.
private enum SyncAccessoryState: Equatable {
    case synced(Date)
    case stale(Date)
    case offline(Date?)
    case noMac(title: String)
    case checking

    var needsAttention: Bool {
        switch self {
        case .synced, .checking: false
        case .stale, .offline, .noMac: true
        }
    }

    var systemImage: String {
        switch self {
        case .synced: "laptopcomputer.and.iphone"
        case .stale: "clock.badge.exclamationmark"
        case .offline: "wifi.slash"
        case .noMac: "laptopcomputer.slash"
        case .checking: "arrow.triangle.2.circlepath"
        }
    }

    var title: String {
        switch self {
        case .synced: "Synced from Mac"
        case .stale: "Mac hasn't synced recently"
        case .offline: "Offline"
        case .noMac(let title): title
        case .checking: "Checking for updates"
        }
    }

    var syncedAt: Date? {
        switch self {
        case .synced(let date), .stale(let date): date
        case .offline(let date): date
        case .noMac, .checking: nil
        }
    }
}

@available(iOS 26, *)
struct SyncStatusTabAccessory: View {
    /// Opens the Continuity Sync section in Settings.
    let onOpenSyncSettings: () -> Void

    @Environment(UsageViewModel.self) private var viewModel
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// A transient note after a refresh that brought nothing new. A refresh can
    /// only re-read what the Mac last published, so it must not imply it fetched.
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        // Ages are minute-granularity; the timeline also re-reads `lastSyncedAt`,
        // which lives in UserDefaults rather than observable state.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = state(now: context.date)
            HStack(spacing: placement == .inline ? 8 : 12) {
                Button(action: onOpenSyncSettings) {
                    statusLabel(state, now: context.date)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(state, now: context.date))
                .accessibilityHint("Opens Continuity Sync settings")

                refreshButton
            }
            .padding(.horizontal, placement == .inline ? 12 : 16)
            .frame(maxHeight: .infinity)
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    // MARK: Status

    private func state(now: Date) -> SyncAccessoryState {
        if viewModel.isLoading || viewModel.isRefreshingContinuitySync {
            return .checking
        }
        switch viewModel.appConnectionStatus {
        case .revoked, .waitingForMac, .needsSetup:
            if viewModel.isOffline { return .offline(viewModel.lastSyncedAt) }
            return .noMac(title: viewModel.appConnectionStatus.title)
        case .checking:
            return .checking
        case .linked, .syncedFromMac, .waitingForDevices:
            break
        }
        if viewModel.isOffline { return .offline(viewModel.lastSyncedAt) }
        guard let syncedAt = viewModel.lastSyncedAt else {
            return .noMac(title: viewModel.appConnectionStatus.title)
        }
        if now.timeIntervalSince(syncedAt) > Constants.syncFallbackThreshold {
            return .stale(syncedAt)
        }
        return .synced(syncedAt)
    }

    @ViewBuilder
    private func statusLabel(_ state: SyncAccessoryState, now: Date) -> some View {
        let tint: Color = state.needsAttention ? .orange : .secondary
        HStack(spacing: 8) {
            Image(systemName: state.systemImage)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 20)

            if placement == .inline {
                // Beside the minimized tab bar: icon and a bare age only.
                if let syncedAt = state.syncedAt {
                    Text(Self.shortAge(from: syncedAt, to: now))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.needsAttention ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
                    if let subtitle = subtitle(state, now: now) {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
            }
        }
    }

    private func subtitle(_ state: SyncAccessoryState, now: Date) -> String? {
        if let feedback { return feedback }
        if let syncedAt = state.syncedAt {
            return "Updated \(Self.longAge(from: syncedAt, to: now))"
        }
        if case .noMac = state { return "Open \(Constants.appDisplayName) on your Mac" }
        return nil
    }

    private func accessibilityLabel(_ state: SyncAccessoryState, now: Date) -> String {
        [state.title, subtitle(state, now: now)].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Refresh

    private var isRefreshing: Bool {
        viewModel.isLoading || viewModel.isRefreshingContinuitySync
    }

    private var refreshButton: some View {
        Button {
            refresh()
        } label: {
            ZStack {
                ProgressView()
                    .opacity(isRefreshing ? 1 : 0)
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .opacity(isRefreshing ? 0 : 1)
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .accessibilityLabel("Check for new usage from your Mac")
    }

    private func refresh() {
        let before = viewModel.lastSyncedAt
        feedbackTask?.cancel()
        feedback = nil
        feedbackTask = Task {
            let outcome = await viewModel.refresh(force: true)
            guard !Task.isCancelled else { return }
            // `.failed` also covers "the Mac's snapshot is older than the fallback
            // threshold", so compare fetch times rather than trusting the outcome alone.
            guard outcome != .updated || viewModel.lastSyncedAt == before else { return }
            feedback = viewModel.isOffline ? "Can't reach iCloud" : "Nothing newer from your Mac"
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }

    // MARK: Formatting

    /// "now", "4m", "3h", "2d" — for the inline placement.
    static func shortAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    /// "just now", "4m ago", "3h ago", "2d ago".
    static func longAge(from date: Date, to now: Date) -> String {
        let short = shortAge(from: date, to: now)
        return short == "now" ? "just now" : "\(short) ago"
    }
}
#endif
