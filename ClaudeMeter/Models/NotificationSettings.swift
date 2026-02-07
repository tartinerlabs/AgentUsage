//
//  NotificationSettings.swift
//  ClaudeMeter
//
//  User-configurable notification preferences
//

#if os(macOS)
import Foundation

/// User-configurable notification settings
struct NotificationSettings: Codable {
    /// Thresholds at which to send notifications (e.g., [25, 50, 75, 100])
    var thresholds: [Int]

    /// Whether to send notifications for session usage
    var notifySession: Bool

    /// Whether to send notifications for opus (all models) usage
    var notifyOpus: Bool

    /// Whether to send notifications for sonnet usage
    var notifySonnet: Bool

    /// Whether to send reset notifications when limit resets
    var notifyOnReset: Bool

    /// Whether to send a notification when extra usage starts
    var notifyExtraUsage: Bool

    /// Default settings with standard thresholds
    static let `default` = NotificationSettings(
        thresholds: [25, 50, 75, 100],
        notifySession: true,
        notifyOpus: true,
        notifySonnet: true,
        notifyOnReset: true,
        notifyExtraUsage: true
    )

    /// Minimal settings (only critical alerts)
    static let minimal = NotificationSettings(
        thresholds: [75, 100],
        notifySession: true,
        notifyOpus: true,
        notifySonnet: false,
        notifyOnReset: false,
        notifyExtraUsage: true
    )

    init(
        thresholds: [Int],
        notifySession: Bool,
        notifyOpus: Bool,
        notifySonnet: Bool,
        notifyOnReset: Bool,
        notifyExtraUsage: Bool = true
    ) {
        self.thresholds = thresholds
        self.notifySession = notifySession
        self.notifyOpus = notifyOpus
        self.notifySonnet = notifySonnet
        self.notifyOnReset = notifyOnReset
        self.notifyExtraUsage = notifyExtraUsage
    }

    // MARK: - Backward-Compatible Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thresholds = try container.decode([Int].self, forKey: .thresholds)
        notifySession = try container.decode(Bool.self, forKey: .notifySession)
        notifyOpus = try container.decode(Bool.self, forKey: .notifyOpus)
        notifySonnet = try container.decode(Bool.self, forKey: .notifySonnet)
        notifyOnReset = try container.decode(Bool.self, forKey: .notifyOnReset)
        notifyExtraUsage = try container.decodeIfPresent(Bool.self, forKey: .notifyExtraUsage) ?? true
    }

    /// All available threshold options
    static let availableThresholds = [25, 50, 75, 90, 100]

    // MARK: - Persistence

    private static let storageKey = "notificationSettings"

    /// Load settings from UserDefaults
    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Save settings to UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: NotificationSettings.storageKey)
    }

    /// Toggle a specific threshold
    mutating func toggleThreshold(_ threshold: Int) {
        if thresholds.contains(threshold) {
            thresholds.removeAll { $0 == threshold }
        } else {
            thresholds.append(threshold)
            thresholds.sort()
        }
    }

    /// Check if a threshold is enabled
    func isThresholdEnabled(_ threshold: Int) -> Bool {
        thresholds.contains(threshold)
    }
}
#endif
