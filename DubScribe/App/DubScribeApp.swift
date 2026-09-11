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

    /// The menu-bar mark: the three-bar form from the app icon.
    ///
    /// This is the asset rather than a drawn `Shape`. A custom `Shape` with
    /// `.fill(...)` and a `.frame(...)` renders as *nothing* here — verified by
    /// A/B against this view with the same build settings, where a text label, an
    /// SF Symbol, and this image all render while the shape produced not one
    /// differing pixel. Menu-bar labels are rasterised by AppKit as template
    /// images, and a bare `Shape` has no intrinsic size to rasterise.
    ///
    /// It is deliberately `.template` so macOS tints it to match the menu bar,
    /// light or dark. That has one consequence worth knowing: a template image
    /// ignores `foregroundStyle`, so the icon cannot turn red while recording —
    /// tried, and it renders white regardless. Recording state is shown by the
    /// menu's own status line instead, which is where it can also say *what* is
    /// happening rather than only *that* something is.
    private var menuBarLabel: some View {
        Image("StatusGlyph")
            .renderingMode(.template)
            .accessibilityLabel(coordinator.recordingState.isRecording
                                ? "DubScribe is recording"
                                : "DubScribe")
    }
}
