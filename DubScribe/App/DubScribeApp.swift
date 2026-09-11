import SwiftUI
import AppKit

@main
struct DubScribeApp: App {

    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        Window("DubScribe", id: "main") {
            ContentView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Settings is its own window rather than a sheet. A sheet runs a modal
        // session, and macOS refuses to quit while one is up — the quit Apple
        // Event comes back as userCanceledErr (-128) *before*
        // applicationShouldTerminate is ever called, so no delegate can rescue
        // it. Measured: sheet => delegate never invoked, quit blocked; plain
        // window => delegate invoked, clean exit. A separate window is also the
        // standard macOS pattern for settings.
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let isRecording = coordinator.recordingState.isRecording

        Image(systemName: isRecording ? "mic.fill" : "mic")
            .foregroundStyle(isRecording ? Color.red : Color.primary)
    }
}
