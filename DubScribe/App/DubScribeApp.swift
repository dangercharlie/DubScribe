import SwiftUI
import AppKit

@main
struct DubScribeApp: App {

    @StateObject private var coordinator = AppCoordinator()

    /// Drives the one-time first-launch nudge. See FirstRunNudge.swift.
    @NSApplicationDelegateAdaptor(FirstRunNudge.self) private var firstRunNudge

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)

        // Settings is its own window. A sheet runs a modal session, and macOS
        // refuses to quit while one is up — the quit Apple Event comes back as
        // userCanceledErr (-128) *before* applicationShouldTerminate is ever
        // called, so no delegate can rescue it. Measured: sheet => delegate
        // never invoked, quit blocked; plain window => delegate invoked, clean
        // exit.
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let isRecording = coordinator.recordingState.isRecording

        StatusGlyph()
            .fill(isRecording ? Color.red : Color.primary)
            .frame(width: 17, height: 15)
            .accessibilityLabel(isRecording ? "DubScribe is recording" : "DubScribe")
    }
}

/// The menu-bar mark: the app icon's bar form, drawn rather than loaded.
///
/// This was an `Image("StatusGlyph")` asset, which rendered as nothing at all.
/// An `Image` that fails to resolve draws empty — no fallback, no error, no log
/// — so the status item became an invisible button. Drawing it as a `Shape`
/// removes that failure mode completely: there is no lookup, no raster, and no
/// scale to go wrong, and it is a true template in the sense that matters (it
/// takes its colour from the surrounding foreground style).
///
/// Bars, not the dot matrix: at this size the dots fall below a pixel and smear
/// into grey. See the icon notes in ideas/002-clip-recorder.
private struct StatusGlyph: Shape {
    /// Relative bar heights, matching the 16px app icon.
    private let heights: [CGFloat] = [0.40, 1.0, 0.60]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let gap = rect.width * 0.22
        let barWidth = (rect.width - gap * CGFloat(heights.count - 1)) / CGFloat(heights.count)
        let radius = min(barWidth / 2, rect.height / 6)

        for (index, height) in heights.enumerated() {
            let barHeight = rect.height * height
            let bar = CGRect(
                x: rect.minX + CGFloat(index) * (barWidth + gap),
                y: rect.midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}
