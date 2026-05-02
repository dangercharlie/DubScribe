import SwiftUI
import AppKit

@main
struct HotkeyRecorderApp: App {

    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        // Main window
        Window("Hotkey Recorder", id: "main") {
            ContentView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // Menu bar extra
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
        HStack(spacing: 4) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .symbolRenderingMode(isRecording ? .palette : .monochrome)
                .foregroundStyle(isRecording ? Color.red : Color.primary)
        }
    }
}
