import SwiftUI
import AppKit

/// The app's primary surface.
///
/// This used to be a secondary menu alongside a 628-line main window. That
/// window was almost entirely a second copy of what is here — its own status
/// line, its own record button, its own permission warning — plus a clip player.
/// Only the player was genuinely unique, so the player moved here and the window
/// went away. DubScribe is now reachable in exactly one place, which is also the
/// place it is most useful.
///
/// Deliberately `.menu`-style: this renders as a real `NSMenu`, so the dropdown
/// is native rather than an imitation of one. That rules out custom views like
/// sliders, which is not a loss — a menu closes the moment you click an item, so
/// a scrubber could never show you anything anyway.
struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    private var state: RecordingState { coordinator.recordingState }
    private var player: AudioPlayer { coordinator.audioPlayer }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusRow

            Divider()

            recordButton

            Divider()

            if let url = coordinator.lastClipURL {
                lastClipItems(url: url)
                Divider()
            }

            permissionItemIfNeeded

            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }

            Button("Reveal Clips Folder") {
                coordinator.revealClipsFolder()
            }

            Divider()

            Button("Quit DubScribe") {
                NSApp.terminate(nil)
            }
        }
        .frame(minWidth: 240)
    }

    // MARK: - Status

    private var statusRow: some View {
        Label {
            Text(state.displayText)
                .font(.system(size: 13, weight: .semibold))
        } icon: {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recordButton: some View {
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
    }

    // MARK: - Last clip

    @ViewBuilder
    private func lastClipItems(url: URL) -> some View {
        // Playback used to live in the main window, complete with a scrubber and
        // a running timer. In a menu it collapses to a single toggle: the menu
        // dismisses on click, so anything that updates over time would be
        // invisible the moment it started moving.
        Button {
            if player.playbackState == .playing {
                player.pause()
            } else {
                if !player.canPlay { player.load(url: url) }
                player.play()
            }
        } label: {
            Label(
                player.playbackState == .playing ? "Stop Playback" : "Play Last Clip",
                systemImage: player.playbackState == .playing ? "stop.fill" : "play.fill"
            )
        }
        .disabled(!player.canPlay && player.playbackState == .playing)

        // Rescues the "I pasted into the wrong window" case without making the
        // user record the same thing twice.
        Button { coordinator.copyLastClipAgain() } label: {
            Label("Copy Last Clip Again", systemImage: "doc.on.doc")
        }

        Button { coordinator.revealLastClip() } label: {
            Label("Show Last Clip in Finder", systemImage: "folder")
        }

        Text(url.lastPathComponent)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
    }

    // MARK: - Permissions

    /// Permission repair, moved out of the main window. A revoked microphone is
    /// the one failure that stops DubScribe working entirely, so it is the one
    /// thing worth interrupting the menu with — and it is surfaced only when it
    /// is actually broken.
    @ViewBuilder
    private var permissionItemIfNeeded: some View {
        if !PermissionHelpers.isMicrophoneAuthorized {
            Button {
                PermissionHelpers.openMicrophoneSettings()
            } label: {
                Label("Microphone Access Required…", systemImage: "mic.slash")
            }
        }
    }

    // MARK: - Status presentation

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
