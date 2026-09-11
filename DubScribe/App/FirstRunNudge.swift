import SwiftUI
import AppKit
import ApplicationServices

/// Handles the once-per-version "What's New" window and the first-launch nudge.
///
/// Both are one-time introductions to the same thing — the app telling you where
/// it lives — so they share one delegate rather than fighting over
/// `applicationDidFinishLaunching`.
///
/// On a genuine first launch the user gets the nudge, not the release notes:
/// being shown "what's new" in an app you have never used is meaningless, and
/// the notes would bury the one thing that actually matters, which is finding
/// the menu-bar item.
@MainActor
final class FirstRunNudge: NSObject, NSApplicationDelegate {

    private static let hasLaunchedKey = "hasLaunchedBefore"
    private static let lastSeenVersionKey = "lastSeenVersion"

    private var whatsNewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: Self.hasLaunchedKey) {
            defaults.set(true, forKey: Self.hasLaunchedKey)
            // Record the version too, so upgrading later does not immediately
            // show notes for a release the user was never really running.
            defaults.set(Self.runningVersion, forKey: Self.lastSeenVersionKey)
            openMenuOnce()
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

    // MARK: - First-run nudge

    /// SwiftUI's `MenuBarExtra` has no public API to open itself, so the menu is
    /// opened the same way a click would open it: by pressing our own status item
    /// through the accessibility API. That is normally a privileged operation,
    /// but an application may always inspect *itself* without any TCC grant,
    /// which is what makes this viable without asking for Accessibility access.
    ///
    /// Best-effort by design. If the press fails the app carries on — a courtesy
    /// that fails is far better than a launch that breaks.
    private func openMenuOnce() {
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if pressStatusItem() { return }
            }
        }
    }

    private func pressStatusItem() -> Bool {
        guard let item = statusItemElement() else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func statusItemElement() -> AXUIElement? {
        let app = AXUIElementCreateApplication(getpid())
        var found: AXUIElement?

        func walk(_ element: AXUIElement, _ depth: Int) {
            if depth > 8 || found != nil { return }
            if role(of: element) == (kAXMenuBarItemRole as String),
               title(of: element) == ProcessInfo.processInfo.processName,
               isStatusItem(element) {
                found = element
                return
            }
            for child in children(of: element) { walk(child, depth + 1) }
        }

        walk(app, 0)
        return found
    }

    /// The app menu's own title item shares the app's name, so name alone is not
    /// enough to identify the status item. The two are distinguishable by
    /// geometry: a real status item has a non-zero size, while the application
    /// menu title reports 0x0.
    private func isStatusItem(_ element: AXUIElement) -> Bool {
        guard let value = attribute(of: element, kAXSizeAttribute) else { return false }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return false }
        return size.width > 0 && size.height > 0
    }

    // MARK: - AX helpers

    private func attribute(of element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        (attribute(of: element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func role(of element: AXUIElement) -> String {
        (attribute(of: element, kAXRoleAttribute) as? String) ?? ""
    }

    private func title(of element: AXUIElement) -> String {
        (attribute(of: element, kAXTitleAttribute) as? String) ?? ""
    }
}
