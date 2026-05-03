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
        let isListening: Bool = {
            if case .listeningForVoice = coordinator.recordingState { return true }
            return false
        }()

        Image(systemName: isRecording ? "mic.fill" : (isListening ? "ear" : "mic"))
            .foregroundStyle(isRecording ? Color.red : (isListening ? Color(hue: 0.62, saturation: 0.6, brightness: 0.8) : Color.primary))
    }
}
