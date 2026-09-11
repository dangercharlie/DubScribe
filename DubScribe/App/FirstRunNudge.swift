import AppKit
import ApplicationServices

/// Handles the one-time first-launch nudge.
///
/// A menu-bar-only app has a discoverability problem: on first run the user is
/// handed a small icon and no indication that it is the entire interface. The
/// app used to solve this by opening a main window, which is exactly the thing
/// that was just removed.
///
/// SwiftUI's `MenuBarExtra` has no public API to open itself, so the menu is
/// opened the same way a click would open it: by pressing our own status item
/// through the accessibility API. That is normally a privileged operation, but
/// an application may always inspect *itself* without any TCC grant, which is
/// what makes this viable without asking the user for Accessibility access.
///
/// This is best-effort by design. If the press fails for any reason the app
/// simply carries on — the nudge is a courtesy, and breaking launch over it
/// would be far worse than a user not seeing it.
@MainActor
final class FirstRunNudge: NSObject, NSApplicationDelegate {

    private static let hasLaunchedKey = "hasLaunchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.hasLaunchedKey) else { return }

        // Recorded immediately rather than after the attempt: a failed press
        // must not mean a second nudge on the next launch.
        defaults.set(true, forKey: Self.hasLaunchedKey)

        Task { @MainActor in
            // The status item does not necessarily exist the instant the app
            // finishes launching, so give it a moment to appear.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if pressStatusItem() { return }
            }
        }
    }

    /// Finds this app's own status item and presses it. Returns whether the
    /// press reported success.
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
