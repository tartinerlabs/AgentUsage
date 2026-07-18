//
//  AppDelegate.swift
//  AgentUsage
//
//  Created by Ru Chern Chong on 3/1/26.
//

#if os(macOS)
import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowObservers: [NSObjectProtocol] = []
    private var onboardingWindow: NSWindow?

    private static let onboardingCompletedKey = "hasCompletedDataAccessOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindowObservers()
        updateActivationPolicy()

        // Set notification delegate to show banners even when app is in foreground
        UNUserNotificationCenter.current().delegate = self

        presentDataAccessOnboardingIfNeeded()
    }

    // MARK: - First-run local data access

    /// Show the one-time local-data-access prompt at first launch when the sandboxed
    /// app has no Full Disk Access or saved folder grant yet. Marked complete once
    /// shown so it never nags again — the setup remains available in Settings.
    private func presentDataAccessOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.onboardingCompletedKey) else { return }

        // Already have access (including a migrated legacy grant): nothing to ask.
        guard !SandboxFolderAccessService.shared.hasAnyAccess else {
            defaults.set(true, forKey: Self.onboardingCompletedKey)
            return
        }

        // Asked at start — mark complete now so any dismissal path is one-and-done.
        defaults.set(true, forKey: Self.onboardingCompletedKey)

        let content = DataAccessOnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.updateActivationPolicy()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Constants.appDisplayName
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
#endif
