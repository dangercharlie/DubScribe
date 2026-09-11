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

    /// Three lines: where it lives, how to start, where it goes.
    ///
    /// Deliberately no key names. The shortcut is a setting, so naming it here
    /// would be wrong for anyone who has changed it, and would go stale the
    /// moment a default changed — on the one screen a user reads once. "A
    /// keyboard shortcut" says everything that stays true. Settings is where the
    /// actual combination belongs.
    ///
    /// The details are one short clause each. Anything longer stops being read,
    /// and each title already carries the point.
    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step(
                symbol: "menubar.rectangle",
                title: "Lives in your menu bar",
                detail: "No window, no Dock icon."
            )
            step(
                symbol: "command",
                title: "Record with a keyboard shortcut",
                detail: "Hold to record, or press to start and stop."
            )
            step(
                symbol: "doc.on.clipboard",
                title: "Goes straight to your clipboard",
                detail: "Paste it wherever you need it."
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
