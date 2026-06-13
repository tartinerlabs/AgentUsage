//
//  AppDelegate.swift
//  ClaudeMeter
//
//  Created by Ru Chern Chong on 3/1/26.
//

import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    @MainActor
    static func activateForMainWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindowObservers()
        updateActivationPolicy()

        // Set notification delegate to show banners even when app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and play sound even when app is in foreground
        [.banner, .sound]
    }

    private func setupWindowObservers() {
        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay to allow window to actually close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateActivationPolicy()
            }
        }

        windowObservers = [willClose]
    }

    private func updateActivationPolicy() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && !isMenuBarExtraWindow(window)
        }

        let newPolicy: NSApplication.ActivationPolicy = hasVisibleWindows ? .regular : .accessory

        if NSApp.activationPolicy() != newPolicy {
            NSApp.setActivationPolicy(newPolicy)
        }
    }

    private func isMenuBarExtraWindow(_ window: NSWindow) -> Bool {
        // MenuBarExtra windows have specific characteristics
        let className = String(describing: type(of: window))
        return className.contains("MenuBarExtra") ||
               className.contains("StatusBar") ||
               window.level == .statusBar ||
               window.styleMask.contains(.borderless) && window.frame.height < 50
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        false
    }
}
