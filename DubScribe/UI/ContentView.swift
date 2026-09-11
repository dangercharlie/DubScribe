import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var permissionsExpanded: Bool = false
    @State private var pulseAnimation = false
    @State private var micGranted = PermissionHelpers.isMicrophoneAuthorized
    @State private var displayDuration: TimeInterval = 0
    @State private var ticker: Timer?

    private var state: RecordingState { coordinator.recordingState }
    private var allGranted: Bool { micGranted }

    var body: some View {
        ZStack {
            // Semantic background rather than a hardcoded gradient, so light and
            // dark mode both work and the window matches the rest of macOS.
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 22)
                    .padding(.horizontal, 24)

                Divider()
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        recordingIndicator
                        statusCard
                        controlsSection
                        lastClipSection
                        retentionNote
                        permissionsSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(width: 460, height: 620)
        .onAppear {
            permissionsExpanded = !allGranted
            if state.isRecording { startTicker() }
        }
        .onDisappear { stopTicker() }
        .onChange(of: state.isRecording) { isRec in
            pulseAnimation = isRec
            if isRec { startTicker() } else { stopTicker(); displayDuration = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permission state when the user returns from System Settings
            micGranted = PermissionHelpers.isMicrophoneAuthorized
            permissionsExpanded = !micGranted
        }
    }

    // MARK: - Ticker
    //
    // Only runs while recording. Previously this was an always-on 10 Hz
    // publisher, which meant an idle menu-bar utility redrew its whole window
    // ten times a second forever.

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if let startedAt = coordinator.recordingState.startedAt {
                    displayDuration = Date().timeIntervalSince(startedAt)
                }
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image("AppMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("DubScribe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut, value: headerSubtitle)
            }

            Spacer()

            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open Settings")
            .help("Open DubScribe settings")
        }
    }

    private var headerSubtitle: String {
        switch state {
        case .recording(_, let trigger):
            switch trigger {
            case .holdHotkey: return "Release \(coordinator.settings.holdHotkey.displayString) to stop"
            case .pushHotkey: return "Press \(coordinator.settings.pushHotkey.displayString) again to stop"
            default: return "Recording in progress"
            }
        default:
            return "\(coordinator.settings.holdHotkey.displayString) to hold · \(coordinator.settings.pushHotkey.displayString) to toggle"
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        ZStack {
            if state.isRecording {
                Circle()
                    .stroke(Color.accentColor.opacity(0.25), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulseAnimation ? 1.22 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.7)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false), value: pulseAnimation)
            }

            Circle()
                .fill(indicatorFill)
                .frame(width: 72, height: 72)

            Image(systemName: indicatorIcon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 112)
        .accessibilityLabel(indicatorAccessibilityLabel)
    }

    private var indicatorFill: some ShapeStyle {
        switch state {
        case .recording:
            return AnyShapeStyle(Color.red)
        case .copied:
            return AnyShapeStyle(Color.green)
        case .failed:
            return AnyShapeStyle(Color.orange)
        default:
            // A mid grey, so the white glyph keeps contrast in both light and
            // dark mode. `.quaternaryLabelColor` was too faint in light mode.
            return AnyShapeStyle(Color(nsColor: .systemGray))
        }
    }

    private var indicatorIcon: String {
        switch state {
        case .idle:          return "mic"
        case .recording:     return "mic.fill"
        case .processing:    return "waveform"
        case .copied:        return "checkmark"
        case .failed:        return "exclamationmark.triangle"
        }
    }

    private var indicatorAccessibilityLabel: String {
        switch state {
        case .idle:          return "Microphone idle"
        case .recording:     return "Recording audio"
        case .processing:    return "Processing recording"
        case .copied:        return "Recording copied to clipboard"
        case .failed(let m): return "Error: \(m)"
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 6) {
            Text(state.displayText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            if case .recording = state {
                Text(durationString(displayDuration))
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Recording duration: \(durationString(displayDuration))")
            } else if coordinator.lastDuration > 0 {
                Text("Last recording: \(durationString(coordinator.lastDuration))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let notice = coordinator.notice {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text(notice)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(CardBackground())
    }

    private func durationString(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let tenths = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }

    // MARK: - Primary Action

    private var controlsSection: some View {
        Button {
            if state.isRecording {
                coordinator.stopRecording()
            } else {
                coordinator.startRecording(trigger: .manual)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 14, weight: .semibold))
                Text(state.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(state.isRecording ? .red : .accentColor)
        .controlSize(.large)
        .help(state.isRecording
              ? "Stop and copy the recording to the clipboard."
              : "Start recording from the selected microphone.")
    }

    // MARK: - Last Clip / Empty State

    @ViewBuilder
    private var lastClipSection: some View {
        if let url = coordinator.lastClipURL {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Last Recording")

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image("ClipGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            HStack(spacing: 6) {
                                if let size = fileSize(url) {
                                    Text(size)
                                }
                                if coordinator.lastDuration > 0 {
                                    Text("· \(durationString(coordinator.lastDuration))")
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    PlaybackControlsView(player: coordinator.audioPlayer, url: url)
                }
                .padding(12)
                .background(CardBackground())

                HStack(spacing: 8) {
                    Button {
                        coordinator.copyLastClipAgain()
                    } label: {
                        Label("Copy Again", systemImage: "doc.on.doc")
                    }
                    .help("Put the last clip back on the clipboard without re-recording.")

                    Button("Reveal in Finder") { coordinator.revealLastClip() }
                        .help("Reveal the last recording in Finder")

                    Spacer()
                }
                .font(.system(size: 12))
            }
        } else {
            VStack(spacing: 10) {
                Image("EmptyState")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .accessibilityHidden(true)

                Text("No recordings yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Use a shortcut, or press Start Recording. The clip lands on your clipboard ready to paste.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(CardBackground())
        }
    }

    private func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        let kb = Double(bytes) / 1024
        return kb < 1024
            ? String(format: "%.1f KB", kb)
            : String(format: "%.2f MB", kb / 1024)
    }

    // MARK: - Retention note

    @ViewBuilder
    private var retentionNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: coordinator.settings.autoDeleteClips ? "clock.arrow.circlepath" : "tray.full")
                .font(.system(size: 11))
                // Decorative: the adjacent text already says this.
                .accessibilityHidden(true)
            Text(retentionDescription)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    private var retentionDescription: String {
        guard coordinator.settings.autoDeleteClips else {
            return "Clips are kept until you delete them. Turn on auto-delete in Settings to reclaim disk automatically."
        }
        let mins = coordinator.settings.clipRetentionMinutes
        let shown = mins == floor(mins) ? String(Int(mins)) : String(format: "%.1f", mins)
        return "Clips move to the Trash \(shown) minute\(mins == 1 ? "" : "s") after they leave the clipboard, so they stay pasteable but don't pile up."
    }

    // MARK: - Permissions Section (Collapsible)

    private var permissionsSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { permissionsExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: micGranted ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(micGranted ? Color.green : Color.orange)
                        .font(.system(size: 12))

                    Text(micGranted ? "Permissions" : "Microphone Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(micGranted ? Color.secondary : Color.orange)

                    Spacer()

                    Image(systemName: permissionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if permissionsExpanded {
                VStack(spacing: 6) {
                    Divider().padding(.horizontal, 4)

                    PermissionRowView(
                        icon: "mic",
                        label: "Microphone",
                        granted: micGranted,
                        action: { PermissionHelpers.openMicrophoneSettings() }
                    )

                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text("Global Hotkeys")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(coordinator.hotkeyManager.hotkeysRegistered ? "Active" : "Check app")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(coordinator.hotkeyManager.hotkeysRegistered
                                             ? Color.green : Color.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(CardBackground(corner: 8))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(CardBackground())
    }
}

// MARK: - Playback Controls

struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayer
    let url: URL

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if player.playbackState == .playing {
                        player.pause()
                    } else {
                        if !player.canPlay { player.load(url: url) }
                        player.play()
                    }
                } label: {
                    Image(systemName: player.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(CircularIconButtonStyle())
                .accessibilityLabel(player.playbackState == .playing ? "Pause playback" : "Play last recording")
                .help(player.playbackState == .playing ? "Pause playback" : "Play the last recorded clip")
                .disabled(!player.canPlay && player.playbackState == .idle)
                .onAppear { if !player.canPlay { player.load(url: url) } }

                Button {
                    if !player.canPlay { player.load(url: url) }
                    player.restart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(CircularIconButtonStyle())
                .accessibilityLabel("Restart playback")
                .help("Restart playback from the beginning")

                if player.duration > 0 {
                    Text("\(timeString(player.currentTime)) / \(timeString(player.duration))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if player.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(nsColor: .quaternaryLabelColor))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(
                                width: geo.size.width * CGFloat(player.duration > 0
                                    ? min(player.currentTime / player.duration, 1.0) : 0),
                                height: 3
                            )
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t) % 60
        let m = Int(t) / 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Shared chrome

/// Standard card container used across the dashboard.
///
/// This is a `View`, not a `ViewModifier`, because call sites use it as
/// `.background(CardBackground())` — a `ViewModifier` would not be accepted
/// there.
struct CardBackground: View {
    var corner: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}

/// Small uppercase section heading.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: configuration.isPressed
                                 ? NSColor.quaternaryLabelColor
                                 : NSColor.controlBackgroundColor))
            )
    }
}

/// Circular icon button for the transport controls.
///
/// `ButtonBorderShape.circle` and `.capsule` are both macOS 14+, and DubScribe
/// targets macOS 13, so the shape is drawn by hand rather than borrowed.
struct CircularIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 26)
            .background(
                Circle().fill(Color(nsColor: configuration.isPressed
                                    ? NSColor.quaternaryLabelColor
                                    : NSColor.controlBackgroundColor))
            )
            .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .contentShape(Circle())
    }
}

struct PermissionRowView: View {
    let icon: String
    let label: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Enable") { action() }
                    .font(.system(size: 11))
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(CardBackground(corner: 8))
    }
}
