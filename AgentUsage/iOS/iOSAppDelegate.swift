//
//  iOSAppDelegate.swift
//  AgentUsage
//

#if os(iOS)
import UIKit
import UserNotifications

final class iOSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
