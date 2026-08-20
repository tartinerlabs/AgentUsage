//
//  iOSAppDelegate.swift
//  AgentUsage
//

#if os(iOS)
import AgentUsageKit
import CloudKit
import UIKit
import UserNotifications

final class iOSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Weak hook from `AgentUsageApp`. Silent CloudKit pushes refresh through the view model.
    weak var viewModel: UsageViewModel?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        #if DEBUG
        print("[NotificationDiagnosis] foreground delegate configured")
        if ProcessInfo.processInfo.arguments.contains("--diagnose-test-notification") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                let result = await NotificationService.shared.sendTestNotification()
                print("[NotificationDiagnosis] test result: \(result)")
            }
        }
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.subscriptionID == UsageSyncService.snapshotSubscriptionID
        else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor [weak self] in
            guard let viewModel = self?.viewModel else {
                completionHandler(.failed)
                return
            }
            _ = await viewModel.refresh(force: true)
            completionHandler(.newData)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        #if DEBUG
        print("[NotificationDiagnosis] willPresent called: \(notification.request.identifier)")
        #endif
        return [.banner, .list, .sound]
    }
}
#endif
