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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var windowObservers: [NSObjectProtocol] = []
    private var onboardingWindow: NSWindow?
    private let onboardingStore = OnboardingStore(platform: .mac)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindowObservers()
        updateActivationPolicy()

        // Set notification delegate to show banners even when app is in foreground
        UNUserNotificationCenter.current().delegate = self

        presentDataAccessOnboardingIfNeeded()
    }

    // MARK: - First-run local data access

    /// Show setup on a new install. Completion and skipping are persisted separately
    /// so dismissing the window does not silently mark setup as finished.
    private func presentDataAccessOnboardingIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-onboarding") {
            presentDataAccessOnboarding()
            return
        }
        #endif
        guard onboardingStore.shouldPresent else { return }
        presentDataAccessOnboarding()
    }

    private func presentDataAccessOnboarding() {
        if let onboardingWindow {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }

        onboardingStore.present()

        let content = DataAccessOnboardingView(onComplete: { [weak self] in
            self?.onboardingStore.complete()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.updateActivationPolicy()
        }, onSkip: { [weak self] in
            self?.onboardingStore.skip()
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.updateActivationPolicy()
        })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
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
        ) { [weak self] notification in
            if let closingWindow = notification.object as? NSWindow,
               closingWindow === self?.onboardingWindow {
                self?.onboardingStore.dismissWithoutCompleting()
                self?.onboardingWindow = nil
            }
            // Delay to allow window to actually close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateActivationPolicy()
            }
        }

        let showOnboarding = NotificationCenter.default.addObserver(
            forName: .showOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentDataAccessOnboarding()
        }

        windowObservers = [didBecomeVisible, willClose, showOnboarding]
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
