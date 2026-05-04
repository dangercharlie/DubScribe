import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var permissionsExpanded: Bool = false
    @State private var pulseAnimation = false
    @State private var micGranted = PermissionHelpers.isMicrophoneAuthorized
    @State private var displayDuration: TimeInterval = 0

    private var state: RecordingState { coordinator.recordingState }
    private var allGranted: Bool { micGranted }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.top, 18)

                ScrollView {
                    VStack(spacing: 18) {
                        recordingIndicator
                        statusCard
                        controlsSection
                        lastClipSection
                        permissionsSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
            }
        }
        .frame(width: 460, height: 600)
        .onAppear {
            permissionsExpanded = !allGranted
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if state.isRecording {
                displayDuration = coordinator.audioRecorder.recordingDuration
            } else {
                displayDuration = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh permission state when user returns from System Settings
            micGranted = PermissionHelpers.isMicrophoneAuthorized
            permissionsExpanded = !micGranted
        }
        .sheet(isPresented: $coordinator.isSettingsOpen) {
            SettingsView().environmentObject(coordinator)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hue: 0.62, saturation: 0.85, brightness: 0.12),
                Color(hue: 0.68, saturation: 0.90, brightness: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DubScribe")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .animation(.easeInOut, value: headerSubtitle)
            }
            Spacer()
            Button {
                coordinator.isSettingsOpen = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
            .help("Open DubScribe settings")
        }
    }

    private var headerSubtitle: String {
        switch state {
        case .listeningForVoice:
            return "Listening for voice activity…"
        case .recording(_, let trigger):
            switch trigger {
            case .holdHotkey: return "Hold \(coordinator.settings.holdHotkey.displayString) to record"
            case .pushHotkey: return "Press \(coordinator.settings.pushHotkey.displayString) again to stop"
            default: return "Recording in progress"
            }
        default:
            return "Hold \(coordinator.settings.holdHotkey.displayString) · Push \(coordinator.settings.pushHotkey.displayString)"
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        ZStack {
            if state.isRecording {
                // Outer pulse ring — only during active recording
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseAnimation ? 1.25 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.8)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false), value: pulseAnimation)
                    .onAppear { pulseAnimation = true }

                Circle()
                    .stroke(Color.red.opacity(0.2), lineWidth: 3)
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .opacity(pulseAnimation ? 0.1 : 0.7)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false).delay(0.15), value: pulseAnimation)
            }

            Circle()
                .fill(indicatorFill)
                .frame(width: 88, height: 88)
                .shadow(color: indicatorShadow, radius: 20, x: 0, y: 4)

            Image(systemName: indicatorIcon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.white)
                // Only breathe gently while recording; completely static otherwise
                .scaleEffect(state.isRecording ? (pulseAnimation ? 1.06 : 1.0) : 1.0)
        }
        .frame(height: 140)
        .onChange(of: state.isRecording) { isRec in
            if isRec {
                pulseAnimation = true
            } else {
                pulseAnimation = false
            }
        }
        .accessibilityLabel(indicatorAccessibilityLabel)
    }

    private var indicatorFill: some ShapeStyle {
        switch state {
        case .recording:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.0, saturation: 0.85, brightness: 0.9),
                         Color(hue: 0.02, saturation: 0.80, brightness: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .copied:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.38, saturation: 0.75, brightness: 0.7),
                         Color(hue: 0.42, saturation: 0.80, brightness: 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .failed:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.08, saturation: 0.85, brightness: 0.8),
                         Color(hue: 0.05, saturation: 0.90, brightness: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .listeningForVoice:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.62, saturation: 0.60, brightness: 0.45),
                         Color(hue: 0.65, saturation: 0.65, brightness: 0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        default:
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var indicatorShadow: Color {
        switch state {
        case .recording: return .red.opacity(0.5)
        case .copied: return .green.opacity(0.4)
        case .listeningForVoice: return Color(hue: 0.62, saturation: 0.6, brightness: 0.5).opacity(0.5)
        default: return .black.opacity(0.4)
        }
    }

    private var indicatorIcon: String {
        switch state {
        case .idle:              return "mic"          // calm, static mic
        case .listeningForVoice: return "ear"          // listening
        case .recording:         return "mic.fill"     // active recording
        case .processing:        return "waveform"
        case .copied:            return "checkmark"
        case .failed:            return "exclamationmark.triangle"
        }
    }

    private var indicatorAccessibilityLabel: String {
        switch state {
        case .idle:              return "Microphone idle"
        case .listeningForVoice: return "Listening for voice"
        case .recording:         return "Recording audio"
        case .processing:        return "Processing recording"
        case .copied:            return "Recording copied to clipboard"
        case .failed(let m):     return "Error: \(m)"
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(spacing: 6) {
            Text(state.displayText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .animation(.easeInOut, value: state.displayText)

            if case .recording = state {
                Text(durationString(displayDuration))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9))
                    .transition(.opacity)
                    .accessibilityLabel("Recording duration: \(durationString(displayDuration))")
            } else if coordinator.lastDuration > 0 && !state.isRecording {
                Text("Last: \(durationString(coordinator.lastDuration))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private func durationString(_ t: TimeInterval) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let tenths = Int((t.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        Button {
            if state.isRecording {
                coordinator.stopRecording()
            } else {
                coordinator.startRecording(trigger: .manual)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: state.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text(state.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(state.isRecording
                          ? Color.red.opacity(0.8)
                          : Color(hue: 0.62, saturation: 0.6, brightness: 0.5))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: state.isRecording)
        .accessibilityLabel(state.isRecording ? "Stop recording" : "Start recording")
        .help(state.isRecording ? "Stop and save the current recording." : "Start recording audio from the selected microphone.")
    }

    // MARK: - Last Clip Section

    @ViewBuilder
    private var lastClipSection: some View {
        if let url = coordinator.lastClipURL {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last Recording")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(1)

                VStack(spacing: 10) {
                    // File info row
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hue: 0.62, saturation: 0.6, brightness: 0.7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let size = fileSize(url) {
                                    Text(size)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                if coordinator.lastDuration > 0 {
                                    Text("· \(durationString(coordinator.lastDuration))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                        }
                        Spacer()
                    }

                    // Playback controls row
                    PlaybackControlsView(player: coordinator.audioPlayer, url: url)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1))
                )

                // Reveal button
                HStack {
                    Spacer()
                    Button("Reveal in Finder") { coordinator.revealLastClip() }
                        .buttonStyle(GhostButtonStyle())
                        .accessibilityLabel("Reveal last recording in Finder")
                        .help("Reveal last recording in Finder")
                }
            }
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

    // MARK: - Permissions Section (Collapsible)

    private var permissionsSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { permissionsExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: micGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(micGranted
                                         ? Color(hue: 0.38, saturation: 0.7, brightness: 0.65)
                                         : .orange)
                        .font(.system(size: 13))

                    Text(micGranted ? "Permissions ✓" : "Microphone Required")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(micGranted ? .white.opacity(0.5) : .orange)

                    Spacer()

                    Image(systemName: permissionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if permissionsExpanded {
                VStack(spacing: 6) {
                    Divider().background(Color.white.opacity(0.06)).padding(.horizontal, 4)

                    PermissionRowView(
                        icon: "mic.fill",
                        label: "Microphone",
                        granted: micGranted,
                        action: { PermissionHelpers.openMicrophoneSettings() }
                    )

                    // Carbon hotkeys — no Accessibility needed
                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 13))
                            .foregroundColor(Color(hue: 0.38, saturation: 0.7, brightness: 0.7))
                            .frame(width: 20)
                        Text("Global Hotkeys (Carbon)")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text(coordinator.hotkeyManager.hotkeysRegistered ? "Active" : "Check app")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(coordinator.hotkeyManager.hotkeysRegistered
                                             ? Color(hue: 0.38, saturation: 0.7, brightness: 0.7)
                                             : .orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.03))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hue: 0.38, saturation: 0.5, brightness: 0.4).opacity(0.3), lineWidth: 1))
                    )
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(micGranted
                                ? Color.white.opacity(0.07)
                                : Color.orange.opacity(0.35),
                                lineWidth: 1)
                )
        )
    }
}

// MARK: - Playback Controls

struct PlaybackControlsView: View {
    @ObservedObject var player: AudioPlayer
    let url: URL

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                // Play / Pause toggle
                Button {
                    if player.playbackState == .playing {
                        player.pause()
                    } else {
                        if !player.canPlay { player.load(url: url) }
                        player.play()
                    }
                } label: {
                    Image(systemName: player.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(PlaybackButtonStyle())
                .accessibilityLabel(player.playbackState == .playing ? "Pause playback" : "Play last recording")
                .help(player.playbackState == .playing ? "Pause playback" : "Play the last recorded WAV file")
                .disabled(!player.canPlay && player.playbackState == .idle)
                .onAppear { if !player.canPlay { player.load(url: url) } }

                // Restart
                Button {
                    if !player.canPlay { player.load(url: url) }
                    player.restart()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PlaybackButtonStyle())
                .accessibilityLabel("Restart playback")
                .help("Restart playback from the beginning")

                // Progress text
                if player.duration > 0 {
                    Text("\(timeString(player.currentTime)) / \(timeString(player.duration))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }

            // Progress bar
            if player.duration > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 3)
                        Capsule()
                            .fill(Color(hue: 0.62, saturation: 0.6, brightness: 0.7))
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

private struct PlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.5 : 0.75))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.09))
            )
    }
}

// MARK: - Shared Styles

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
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
                .font(.system(size: 13))
                .foregroundColor(granted ? Color(hue: 0.38, saturation: 0.7, brightness: 0.7) : .orange)
                .frame(width: 20)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            if granted {
                Text("Granted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hue: 0.38, saturation: 0.7, brightness: 0.7))
            } else {
                Button("Enable") { action() }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(granted
                            ? Color(hue: 0.38, saturation: 0.5, brightness: 0.4).opacity(0.3)
                            : Color.orange.opacity(0.25),
                            lineWidth: 1))
        )
        .accessibilityLabel(granted
                            ? "\(label) permission granted"
                            : "\(label) permission required — tap Enable")
    }
}
