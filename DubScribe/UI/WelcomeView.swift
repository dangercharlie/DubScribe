import SwiftUI
import AppKit

/// Shown once, ever, on a genuine first launch.
///
/// A menu-bar-only app has a discoverability problem that a normal app does not:
/// there is no window, no Dock icon, and nothing to double-click. The user has
/// launched something and, as far as the screen is concerned, nothing happened —
/// the app's entire interface is a small icon they have not learned to look for
/// yet. Recordia solves this the same way, and the pattern is worth copying: say
/// what this is, say where it lives, and say what to press.
///
/// The window is deliberately small and single-purpose. It is not a wizard, it
/// does not ask anything, and it does not block — one button, and it is gone for
/// good.
struct WelcomeView: View {
    /// Read from the live settings rather than written out as literals.
    ///
    /// The shortcut shown here has to be the shortcut that actually works. A
    /// hardcoded "⌃⌥Space" is correct only until the default changes, and the
    /// screen a new user reads once is the worst place in the app to be wrong.
    let holdHotkey: Hotkey
    let pushHotkey: Hotkey
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            icon

            Text("Welcome to DubScribe")
                .font(.system(size: 21, weight: .bold))
                .padding(.top, 18)

            Text("Low-friction audio capture")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            steps
                .padding(.top, 22)

            Button("Get Started") { onGetStarted() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
                .padding(.bottom, 24)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var icon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 76, height: 76)
            .padding(.top, 30)
            .accessibilityHidden(true)
    }

    /// Three short facts, each with the phrase that matters in a heavier weight.
    ///
    /// The temptation is a paragraph. What a first-time user actually needs is
    /// the shape of the thing: where it lives, how to trigger it, and what
    /// happens next. Anything longer does not get read.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(
                symbol: "menubar.rectangle",
                title: "It lives in your menu bar",
                detail: "No window, no Dock icon. The icon up there is the whole app."
            )
            step(
                symbol: "command",
                title: "Hold \(holdHotkey.displayString) to record",
                detail: "Release to stop. Press \(pushHotkey.displayString) instead if you prefer a toggle."
            )
            step(
                symbol: "doc.on.clipboard",
                title: "It lands on your clipboard",
                detail: "Paste it wherever you need it. There is nothing to save or find."
            )
        }
        .padding(.horizontal, 34)
    }

    private func step(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}
