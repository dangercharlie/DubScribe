import SwiftUI
import AppKit

/// Shown once after an update.
///
/// This is not a setting and is not in Settings. It happens when the running
/// version differs from the last one the user has seen, which is the only moment
/// it can say something the user does not already know. A permanently available
/// "What's New" menu item would mostly be a way to re-read things you have
/// already been told.
///
/// The window is modelled on the standard macOS about-panel layout: icon and
/// version at the top, a short list, and a clear way out. It is deliberately not
/// modal and does not steal focus beyond being brought forward once — the app is
/// usable while it is open, and the menu bar still works behind it.
struct WhatsNewView: View {
    let release: ReleaseNotes.Release
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 16) {
                ForEach(release.items) { item in
                    itemRow(item)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 8)

            footer
        }
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            // The bundle's app icon. An .appiconset is not reliably reachable
            // through NSImage(named:), so this asks the running app instead.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("What's new in \(release.version)")
                    .font(.system(size: 19, weight: .bold))
                Text(release.tagline)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    // MARK: - Items

    private func itemRow(_ item: ReleaseNotes.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }

            Spacer(minLength: 0)
        }
        // One VoiceOver stop per item rather than an icon, a heading and a
        // paragraph as three separate fragments. The label is stated explicitly:
        // `.combine` alone left the text unreadable in testing (the static texts
        // reported empty titles), so the item is described deliberately instead
        // of relying on the combination to work out what to say.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title). \(item.detail)")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 9) {
            Spacer()

            // Opens the bundled CHANGELOG.md, not a URL.
            //
            // The obvious implementation is a link to the GitHub blob, and that
            // is what this was first written as. It contradicts the app's own
            // promise that it makes no network calls of any kind — a button whose
            // entire job is to start one. The changelog ships inside the bundle,
            // so the long form is available offline and the promise holds.
            Button("Release Notes") { openBundledChangelog() }
                .controlSize(.large)

            Button("Continue") { onClose() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Closes this window")
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 22)
    }

    /// Opens the bundled changelog in the user's default editor.
    ///
    /// A raw `.md` is not something macOS has a guaranteed viewer for, so this
    /// hands it to whatever the user has associated with Markdown. If nothing is
    /// associated, the file is revealed in the Finder rather than the button
    /// doing nothing — silence would read as a broken button.
    private func openBundledChangelog() {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
            NSSound.beep()
            return
        }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
