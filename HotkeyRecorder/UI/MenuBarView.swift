import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status header
            Label {
                Text(coordinator.recordingState.displayText)
                    .font(.system(size: 13, weight: .semibold))
            } icon: {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Start / Stop
            Button {
                if coordinator.recordingState.isRecording {
                    coordinator.stopRecording()
                } else {
                    coordinator.startRecording()
                }
            } label: {
                Label(
                    coordinator.recordingState.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: coordinator.recordingState.isRecording ? "stop.circle" : "record.circle"
                )
            }

            Divider()

            // Last clip
            if let url = coordinator.lastClipURL {
                Button {
                    coordinator.revealLastClip()
                } label: {
                    Label("Reveal Last Clip", systemImage: "waveform")
                }
                Text(url.lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)

                Divider()
            }

            // Window
            Button("Open Main Window") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }

            Button("Reveal Clips Folder") {
                coordinator.revealClipsFolder()
            }

            Divider()

            Button("Quit Hotkey Recorder") {
                NSApp.terminate(nil)
            }
        }
        .frame(minWidth: 220)
    }

    private var statusIcon: String {
        switch coordinator.recordingState {
        case .idle:       return "mic.slash"
        case .recording:  return "mic.fill"
        case .processing: return "waveform"
        case .copied:     return "checkmark.circle"
        case .failed:     return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch coordinator.recordingState {
        case .recording:  return .red
        case .copied:     return .green
        case .failed:     return .orange
        default:          return .secondary
        }
    }
}
