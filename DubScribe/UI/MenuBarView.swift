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
///
/// The middle section nests the settings that are *situational*: the ones you
/// reach for while you are working, rather than while you are configuring. They
/// remain in Settings as well; this is a second, closer handle on the same
/// state, not a replacement. Anything you would only ever set once — shortcuts,
/// sounds, the size budget — is left to Settings alone.
struct MenuBarView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    private var state: RecordingState { coordinator.recordingState }
    private var player: AudioPlayer { coordinator.audioPlayer }
    private var settings: AppSettings { coordinator.settings }

    /// Enumerated on each open rather than cached: devices come and go (a
    /// headset connects, a display with a microphone is unplugged) and a stale
    /// list is worse than a small cost on a menu that is opened rarely.
    private var devices: [AudioInputDevice] { AudioInputDevice.availableDevices() }

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

            situationalSettings

            Divider()

            Button { coordinator.revealClipsFolder() } label: {
                Label("Open Clips Folder", systemImage: "folder")
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Button { NSApp.terminate(nil) } label: {
                Label("Quit DubScribe", systemImage: "power")
            }
        }
        .frame(minWidth: 250)
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

    // MARK: - Situational settings

    @ViewBuilder
    private var situationalSettings: some View {
        Menu {
            // A radio list, so the current device is visible without opening
            // Settings to check which one is selected.
            Picker("Microphone", selection: Binding(
                get: { settings.selectedInputDeviceID ?? "system_default" },
                set: { id in
                    coordinator.settings.selectedInputDeviceID = id == "system_default" ? nil : id
                    coordinator.applySettings()
                }
            )) {
                ForEach(devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Microphone", systemImage: "mic")
        }

        toggle("Show Level Indicator", systemImage: "waveform",
               isOn: $coordinator.settings.showRecordingHUD)
        toggle("Pause Media While Recording", systemImage: "pause.circle",
               isOn: $coordinator.settings.pauseMediaDuringRecording)
        toggle("Mute System Audio", systemImage: "speaker.slash",
               isOn: $coordinator.settings.muteSystemAudioDuringRecording)
        toggle("Delete Clips Automatically", systemImage: "trash",
               isOn: $coordinator.settings.autoDeleteClips)
    }

    /// A menu checkmark rather than a switch.
    ///
    /// `.menu` style has no room for a switch control, and a checkmark is the
    /// native way for a menu to express "this is on" — it is also what the
    /// System Settings and Finder menus use. The state is saved on every change
    /// exactly as the Settings window does, so the two surfaces cannot drift.
    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: systemImage)
        }
        .onChange(of: isOn.wrappedValue) { _ in
            coordinator.applySettings()
            // Deletion state changes should take effect at once rather than at
            // the next sweep interval.
            if title == "Delete Clips Automatically" { coordinator.clipStore.sweep() }
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
