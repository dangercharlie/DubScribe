import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showSettings = false
    @State private var pulseAnimation = false

    private var state: RecordingState { coordinator.recordingState }

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection
                    .padding(.top, 28)
                    .padding(.horizontal, 28)

                // Divider
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.top, 18)

                // Main content
                ScrollView {
                    VStack(spacing: 20) {
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
        .frame(width: 460, height: 580)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(coordinator)
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
                Text("Hotkey Recorder")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Hold \(coordinator.settings.hotkey.displayString) to record")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        ZStack {
            // Outer pulse ring (only when recording)
            if state.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseAnimation ? 1.25 : 1.0)
                    .opacity(pulseAnimation ? 0 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: false),
                        value: pulseAnimation
                    )
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }

                Circle()
                    .stroke(Color.red.opacity(0.2), lineWidth: 3)
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                    .opacity(pulseAnimation ? 0.1 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: false).delay(0.15),
                        value: pulseAnimation
                    )
            }

            // Inner circle
            Circle()
                .fill(indicatorFill)
                .frame(width: 88, height: 88)
                .shadow(color: indicatorShadow, radius: 20, x: 0, y: 4)

            Image(systemName: indicatorIcon)
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(.white)
                .scaleEffect(state.isRecording ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: state.isRecording)
        }
        .frame(height: 140)
        .onChange(of: state.isRecording) { recording in
            if !recording { pulseAnimation = false }
        }
    }

    private var indicatorFill: some ShapeStyle {
        switch state {
        case .recording:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.0, saturation: 0.85, brightness: 0.9),
                         Color(hue: 0.02, saturation: 0.80, brightness: 0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .copied:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.38, saturation: 0.75, brightness: 0.7),
                         Color(hue: 0.42, saturation: 0.80, brightness: 0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .failed:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hue: 0.08, saturation: 0.85, brightness: 0.8),
                         Color(hue: 0.05, saturation: 0.90, brightness: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        default:
            return AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.15), Color.white.opacity(0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
    }

    private var indicatorShadow: Color {
        switch state {
        case .recording: return .red.opacity(0.5)
        case .copied: return .green.opacity(0.4)
        default: return .black.opacity(0.4)
        }
    }

    private var indicatorIcon: String {
        switch state {
        case .idle: return "mic.slash"
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle"
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
                Text(durationString(coordinator.audioRecorder.recordingDuration))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.red.opacity(0.9))
                    .transition(.opacity)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
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
        HStack(spacing: 12) {
            // Primary record/stop button
            Button {
                if state.isRecording {
                    coordinator.stopRecording()
                } else {
                    coordinator.startRecording()
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
        }
    }

    // MARK: - Last Clip

    @ViewBuilder
    private var lastClipSection: some View {
        if let url = coordinator.lastClipURL {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last Recording")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(1)

                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hue: 0.62, saturation: 0.6, brightness: 0.7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                        if let size = fileSize(url) {
                            Text(size)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    Button("Reveal") {
                        coordinator.revealLastClip()
                    }
                    .buttonStyle(GhostButtonStyle())
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
            }
        }
    }

    private func fileSize(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return nil }
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.2f MB", kb / 1024)
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionsSection: some View {
        VStack(spacing: 8) {
            // Microphone status
            PermissionRowView(
                icon: "mic.fill",
                label: "Microphone",
                granted: PermissionHelpers.isMicrophoneAuthorized,
                action: {
                    if !PermissionHelpers.isMicrophoneAuthorized {
                        PermissionHelpers.openMicrophoneSettings()
                    }
                }
            )
            // Accessibility status (for global hotkey)
            PermissionRowView(
                icon: "keyboard",
                label: "Accessibility (Global Hotkey)",
                granted: coordinator.hotkeyManager.isAccessibilityGranted,
                action: {
                    if !coordinator.hotkeyManager.isAccessibilityGranted {
                        coordinator.hotkeyManager.requestAccessibilityIfNeeded()
                    }
                }
            )
        }
    }
}

// MARK: - Supporting Views

private struct GhostButtonStyle: ButtonStyle {
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

private struct PermissionRowView: View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(granted
                            ? Color(hue: 0.38, saturation: 0.5, brightness: 0.4).opacity(0.4)
                            : Color.orange.opacity(0.3),
                            lineWidth: 1))
        )
    }
}
