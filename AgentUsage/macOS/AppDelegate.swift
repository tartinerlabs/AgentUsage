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
    private var statusItemRightClickMonitor: Any?
    private var didAttachStatusItemMenuRecognizer = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindowObservers()
        installStatusItemMenu()
        updateActivationPolicy()

        // Set notification delegate to show banners even when app is in foreground
        UNUserNotificationCenter.current().delegate = self
    }

    /// Closes the dashboard and onboarding windows, leaving the menu bar extra running.
    static func closeMainWindows() {
        for window in NSApp.windows where window.isVisible && !isMenuBarExtraWindow(window) {
            window.close()
        }
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
            // `queue: .main` guarantees main-thread delivery, but the closure is
            // `@Sendable` and so nonisolated to the compiler. Assert the isolation we
            // already have rather than hopping and losing ordering.
            MainActor.assumeIsolated {
                self?.attachStatusItemMenuRecognizerIfNeeded()
                self?.updateActivationPolicy()
            }
        }

        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Delay to allow window to actually close
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    MainActor.assumeIsolated {
                        self?.updateActivationPolicy()
                    }
                }
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
        Self.isMenuBarExtraWindow(window)
    }

    static func isMenuBarExtraWindow(_ window: NSWindow) -> Bool {
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

    // MARK: - Status item menu

    /// SwiftUI `MenuBarExtra` has no context-menu API, so right-click on the status
    /// item is observed here and presents the status item menu (Refresh, Open
    /// Dashboard, Settings…, Quit). Left-click still opens the popover.
    private func installStatusItemMenu() {
        statusItemRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            // `NSEvent` is explicitly non-Sendable, so it cannot be the generic
            // result of `assumeIsolated`. Decide on the main actor, then hand the
            // event back (or swallow it) outside the isolated region.
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, Self.isStatusItemEvent(event) else { return false }
                self.popStatusItemMenu(with: event)
                return true
            }
            return consumed ? nil : event
        }
        attachStatusItemMenuRecognizerIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.attachStatusItemMenuRecognizerIfNeeded()
        }
    }

    private func attachStatusItemMenuRecognizerIfNeeded() {
        guard !didAttachStatusItemMenuRecognizer else { return }
        guard let button = Self.findStatusBarButton() else { return }

        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleStatusItemRightClick(_:)))
        recognizer.buttonMask = 1 << 1
        recognizer.numberOfClicksRequired = 1
        button.addGestureRecognizer(recognizer)
        didAttachStatusItemMenuRecognizer = true
    }

    @objc private func handleStatusItemRightClick(_ sender: NSClickGestureRecognizer) {
        guard sender.state == .ended, let view = sender.view else { return }
        Self.makeStatusItemMenu(target: self).popUp(positioning: nil, at: sender.location(in: view), in: view)
    }

    // The status item menu has no SwiftUI environment, so its actions post
    // notifications that the MenuBarExtra label's tasks in `AgentUsageApp` handle
    // with the same view model, tab selection, and `openWindow` the popover uses.

    @objc func refreshFromStatusItemMenu(_ sender: Any?) {
        NotificationCenter.default.post(name: .refreshUsageRequested, object: nil)
    }

    @objc func openDashboardFromStatusItemMenu(_ sender: Any?) {
        NotificationCenter.default.post(name: .showDashboard, object: nil)
    }

    @objc func openSettingsFromStatusItemMenu(_ sender: Any?) {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let button = findStatusBarButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findStatusBarButton(in: subview) {
                return button
            }
        }
        return nil
    }

    private static func isStatusItemEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        let className = String(describing: type(of: window))
        if className.contains("NSStatusBarWindow") { return true }
        if window.contentView is NSStatusBarButton { return true }
        if window.contentView?.hitTest(event.locationInWindow) is NSStatusBarButton { return true }
        return false
    }

    private func popStatusItemMenu(with event: NSEvent) {
        guard let view = event.window?.contentView else { return }
        NSMenu.popUpContextMenu(Self.makeStatusItemMenu(target: self), with: event, for: view)
    }

    /// Builds the status item's right-click menu. Refresh, Open Dashboard, and
    /// Settings… dispatch to `target`; Quit goes to `NSApplication` through the
    /// responder chain, as before.
    static func makeStatusItemMenu(target: AppDelegate?) -> NSMenu {
        let menu = NSMenu()

        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(AppDelegate.refreshFromStatusItemMenu(_:)),
            keyEquivalent: ""
        )
        refresh.target = target
        menu.addItem(refresh)

        let dashboard = NSMenuItem(
            title: "Open Dashboard",
            action: #selector(AppDelegate.openDashboardFromStatusItemMenu(_:)),
            keyEquivalent: ""
        )
        dashboard.target = target
        menu.addItem(dashboard)

        // Matches the app menu's Settings command (⌘,).
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettingsFromStatusItemMenu(_:)),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = .command
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit \(Constants.appDisplayName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        ))
        return menu
    }
}
#endif
