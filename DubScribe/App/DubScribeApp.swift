import SwiftUI
import AppKit

@main
struct DubScribeApp: App {

    @Environment(\.openWindow) private var openWindow
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
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
        let isListening: Bool = {
            if case .listeningForVoice = coordinator.recordingState { return true }
            return false
        }()

        Image(systemName: isRecording ? "mic.fill" : (isListening ? "ear" : "mic"))
            .foregroundStyle(isRecording ? Color.red : (isListening ? Color(hue: 0.62, saturation: 0.6, brightness: 0.8) : Color.primary))
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        coordinator.isSettingsOpen = true
    }
}
