import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    private var state: RecordingState { coordinator.recordingState }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(state.displayText)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Button {
                if state.isRecording {
                    coordinator.stopRecording()
                } else {
                    coordinator.startRecording(trigger: .manual)
                }
            } label: {
                Label(
                    state.isRecording ? "Stop & Copy" : "Start Recording",
                    systemImage: state.isRecording ? "stop.circle" : "record.circle"
                )
            }

            Divider()

            if let url = coordinator.lastClipURL {
                Button { coordinator.revealLastClip() } label: {
                    Label("Reveal Last Clip", systemImage: "waveform")
                }

                // Rescues the "I pasted into the wrong window" case without
                // making the user record the same thing twice.
                Button { coordinator.copyLastClipAgain() } label: {
                    Label("Copy Last Clip Again", systemImage: "doc.on.doc")
                }

                Text(url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)

                Divider()
            }

            Button("Open DubScribe") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button("Reveal Clips Folder") {
                coordinator.revealClipsFolder()
            }

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                coordinator.isSettingsOpen = true
            }

            Divider()

            Button("Quit DubScribe") {
                NSApp.terminate(nil)
            }
        }
        .frame(minWidth: 240)
    }

    private var statusIcon: String {
        switch state {
        case .idle:              return "mic"
        case .recording:         return "mic.fill"
        case .processing:        return "waveform"
        case .copied:            return "checkmark.circle"
        case .failed:            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch state {
        case .recording:         return .red
        case .copied:            return .green
        case .failed:            return .orange
        default:                 return .secondary
        }
    }
}
