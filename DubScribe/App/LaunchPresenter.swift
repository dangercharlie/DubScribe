import SwiftUI
import AppKit

/// Owns the two windows the app shows on its own initiative.
///
/// They are mutually exclusive by design, and a genuine first launch gets the
/// welcome rather than the release notes: being told what changed in an app you
/// have never used is meaningless, and it would bury the thing that actually
/// matters, which is finding out where the app lives and what to press.
///
/// Both are one-time — the welcome once ever, the notes once per version — and
/// both are driven from stored state rather than from a setting, because neither
/// is something the user should have to opt out of. This is the only place in
/// the app that activates itself or takes key focus, which is why the two live
/// together rather than being scattered.
@MainActor
final class LaunchPresenter: NSObject, NSApplicationDelegate {

    private static let hasLaunchedKey = "hasLaunchedBefore"
    private static let lastSeenVersionKey = "lastSeenVersion"

    private var welcomeWindow: NSWindow?
    private var whatsNewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: Self.hasLaunchedKey) {
            defaults.set(true, forKey: Self.hasLaunchedKey)
            // Record the version too, so upgrading later does not immediately
            // show notes for a release the user was never really running.
            defaults.set(Self.runningVersion, forKey: Self.lastSeenVersionKey)
            // A window, not the auto-opened menu. The menu was tried first and it
            // is the wrong shape for this: a dropdown flashes open, shows a list
            // of commands, and closes the moment you click anywhere — so the one
            // thing a new user needs, "this is where the app lives and this is
            // what to press", is exactly what it cannot hold.
            showWelcome()
            return
        }

        let seen = defaults.string(forKey: Self.lastSeenVersionKey)
        if seen != Self.runningVersion {
            defaults.set(Self.runningVersion, forKey: Self.lastSeenVersionKey)
            // Only for a version that actually has notes. This also covers a user
            // upgrading from a release so old it predates this mechanism.
            if ReleaseNotes.current != nil {
                showWhatsNew()
            }
        }
    }

    private static var runningVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Welcome

    private func showWelcome() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DubScribe"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        let settings = AppSettings.load()
        window.contentView = NSHostingView(rootView: WelcomeView(
            holdHotkey: settings.holdHotkey,
            pushHotkey: settings.pushHotkey
        ) { [weak self] in
            self?.welcomeWindow?.close()
            self?.welcomeWindow = nil
            // Meeting the app is not the same as being told what changed, so the
            // first launch does not also queue up release notes.
        })
        window.center()

        // An LSUIElement app does not activate on its own, so without this the
        // welcome window opens behind whatever is frontmost — which for a
        // first-run greeting is a total failure of the exercise.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        welcomeWindow = window
    }

    // MARK: - What's New

    private func showWhatsNew() {
        guard let release = ReleaseNotes.current else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DubScribe"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WhatsNewView(release: release) { [weak self] in
            self?.closeWhatsNew()
        })
        window.center()
        // An LSUIElement app does not become active on its own, so without this
        // the window opens behind whatever is frontmost and its default button
        // renders as an inactive grey — the prominent style only draws blue while
        // the window is key. Activating is right for this one moment: the window
        // is a deliberate, once-per-version interruption, not a background event.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        whatsNewWindow = window
    }

    private func closeWhatsNew() {
        whatsNewWindow?.close()
        whatsNewWindow = nil
    }
}
