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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure only one instance is running
        if isAnotherInstanceRunning() {
            activateExistingInstanceAndQuit()
            return
        }

        setupWindowObservers()
        updateActivationPolicy()

        // Set notification delegate to show banners even when app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Single Instance Management

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let instances = runningApps.filter { $0.bundleIdentifier == bundleIdentifier }

        // More than one instance means another is already running
        return instances.count > 1
    }

    private func activateExistingInstanceAndQuit() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            NSApp.terminate(nil)
            return
        }

        // Find and activate the existing instance
        let runningApps = NSWorkspace.shared.runningApplications
        if let existingInstance = runningApps.first(where: {
            $0.bundleIdentifier == bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }) {
            existingInstance.activate()
        }

        // Terminate this instance
        NSApp.terminate(nil)
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
        let didBecomeVisible = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateActivationPolicy()
        }

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

        windowObservers = [didBecomeVisible, willClose]
    }

    private func updateActivationPolicy() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            window.isVisible && !isMenuBarExtraWindow(window)
        }

        let newPolicy: NSApplication.ActivationPolicy = hasVisibleWindows ? .regular : .accessory

        if NSApp.activationPolicy() != newPolicy {
            NSApp.setActivationPolicy(newPolicy)

            // When switching to regular, activate the app to show menu bar
            if newPolicy == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
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
