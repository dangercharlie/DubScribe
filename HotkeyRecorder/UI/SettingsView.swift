import SwiftUI
import Carbon

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var isRecordingHold = false
    @State private var isRecordingPush = false
    @State private var hotkeyConflict: String? = nil
    @State private var availableDevices: [AudioInputDevice] = []

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: 0.62, saturation: 0.85, brightness: 0.12),
                    Color(hue: 0.68, saturation: 0.90, brightness: 0.08)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button { coordinator.applySettings(); dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("Close settings")
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().background(Color.white.opacity(0.08))

                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Recording Shortcuts
                        settingsSection("Recording Shortcuts") {
                            VStack(spacing: 12) {
                                if let conflict = hotkeyConflict {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 12))
                                        Text(conflict)
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 4)
                                }

                                hotkeyRow(
                                    label: "Hold to Record",
                                    description: "Hold to record, release to stop",
                                    hotkey: coordinator.settings.holdHotkey,
                                    isRecording: $isRecordingHold,
                                    onNew: { newKey in
                                        if newKey == coordinator.settings.pushHotkey {
                                            hotkeyConflict = "Hold and Push hotkeys must be different."
                                        } else {
                                            hotkeyConflict = nil
                                            coordinator.settings.holdHotkey = newKey
                                            coordinator.applySettings()
                                        }
                                    },
                                    onReset: { coordinator.resetHoldHotkey() },
                                    helpText: "Hold this shortcut to record. Release to stop and copy to clipboard."
                                )

                                Divider().background(Color.white.opacity(0.06))

                                hotkeyRow(
                                    label: "Push to Record",
                                    description: "Press once to start, again to stop",
                                    hotkey: coordinator.settings.pushHotkey,
                                    isRecording: $isRecordingPush,
                                    onNew: { newKey in
                                        if newKey == coordinator.settings.holdHotkey {
                                            hotkeyConflict = "Push and Hold hotkeys must be different."
                                        } else {
                                            hotkeyConflict = nil
                                            coordinator.settings.pushHotkey = newKey
                                            coordinator.applySettings()
                                        }
                                    },
                                    onReset: { coordinator.resetPushHotkey() },
                                    helpText: "Press once to start recording, press again to stop."
                                )
                            }
                        }

                        // 2. Audio Input
                        settingsSection("Audio Input") {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Input Source")
                                        .settingsLabel()
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { coordinator.settings.selectedInputDeviceID ?? "system_default" },
                                        set: { id in
                                            coordinator.settings.selectedInputDeviceID = id == "system_default" ? nil : id
                                            coordinator.applySettings()
                                        }
                                    )) {
                                        ForEach(availableDevices) { device in
                                            Text(device.name).tag(device.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 200)
                                    .accessibilityLabel("Audio input source")
                                    .help("Select the microphone or audio input device to use for recordings.")
                                }

                                Divider().background(Color.white.opacity(0.06))

                                Toggle(isOn: $coordinator.settings.playSounds) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Play sounds on record/stop")
                                            .settingsLabel()
                                        Text("Plays a Tink sound when recording starts and stops.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                }
                                .toggleStyle(CustomToggleStyle())
                                .onChange(of: coordinator.settings.playSounds) { _ in coordinator.applySettings() }
                                .accessibilityLabel("Play sounds on record and stop")
                            }
                        }

                        // 3. Voice Activation
                        settingsSection("Voice Activation") {
                            VStack(spacing: 12) {
                                Toggle(isOn: $coordinator.settings.voiceActivationEnabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Enable Voice Activation")
                                            .settingsLabel()
                                        Text("Automatically starts recording when voice is detected.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                }
                                .toggleStyle(CustomToggleStyle())
                                .onChange(of: coordinator.settings.voiceActivationEnabled) { _ in
                                    coordinator.applySettings()
                                }
                                .accessibilityLabel("Enable voice activation")

                                if coordinator.settings.voiceActivationEnabled {
                                    Divider().background(Color.white.opacity(0.06))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Input Threshold")
                                                .settingsLabel()
                                            Spacer()
                                            Text("\(Int(coordinator.settings.voiceActivationThreshold * 100))%")
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        Slider(
                                            value: $coordinator.settings.voiceActivationThreshold,
                                            in: 0.005...0.3
                                        )
                                        .accentColor(Color(hue: 0.62, saturation: 0.6, brightness: 0.7))
                                        .onChange(of: coordinator.settings.voiceActivationThreshold) { _ in
                                            coordinator.applySettings()
                                        }
                                        .accessibilityLabel("Voice activation input threshold")
                                        .accessibilityValue("\(Int(coordinator.settings.voiceActivationThreshold * 100)) percent")
                                        .help("Raise the threshold to avoid triggering recordings from background noise.")
                                        HStack {
                                            Text("Quiet").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                                            Spacer()
                                            Text("Loud").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                                        }
                                        Text("Raise the threshold if background noise starts recordings accidentally.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                    }

                                    Divider().background(Color.white.opacity(0.06))

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Stop Delay")
                                                .settingsLabel()
                                            Spacer()
                                            Text(String(format: "%.1fs", coordinator.settings.voiceActivationStopDelay))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        Slider(
                                            value: $coordinator.settings.voiceActivationStopDelay,
                                            in: 0.3...3.0,
                                            step: 0.1
                                        )
                                        .accentColor(Color(hue: 0.62, saturation: 0.6, brightness: 0.7))
                                        .onChange(of: coordinator.settings.voiceActivationStopDelay) { _ in
                                            coordinator.applySettings()
                                        }
                                        .accessibilityLabel("Voice activation stop delay")
                                        .accessibilityValue(String(format: "%.1f seconds", coordinator.settings.voiceActivationStopDelay))
                                        .help("How long to wait in silence before stopping the recording automatically.")
                                        Text("Delay before stopping after silence. Prevents cutting off between words.")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                }
                            }
                        }

                        // 4. General
                        settingsSection("General") {
                            VStack(spacing: 10) {
                                Toggle(isOn: Binding(
                                    get: { coordinator.loginItemManager.isEnabled },
                                    set: { coordinator.loginItemManager.setEnabled($0) }
                                )) {
                                    Text("Launch at Login")
                                        .settingsLabel()
                                }
                                .toggleStyle(CustomToggleStyle())
                                .accessibilityLabel("Launch DubScribe at login")

                                Divider().background(Color.white.opacity(0.06))

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Clips Folder")
                                            .settingsLabel()
                                        Text(FileManagerHelpers.clipsDirectory.path)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.28))
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button("Reveal") { coordinator.revealClipsFolder() }
                                        .buttonStyle(SettingsGhostButtonStyle())
                                        .accessibilityLabel("Reveal clips folder in Finder")
                                        .help("Reveal the DubScribe clips folder in Finder")
                                }
                            }
                        }

                        // 5. Permissions
                        settingsSection("Permissions") {
                            VStack(spacing: 10) {
                                settingsPermissionRow(
                                    icon: "mic.fill",
                                    title: "Microphone",
                                    description: "Required to record audio.",
                                    granted: PermissionHelpers.isMicrophoneAuthorized,
                                    action: { PermissionHelpers.openMicrophoneSettings() }
                                )
                                settingsPermissionRow(
                                    icon: "keyboard",
                                    title: "Accessibility",
                                    description: "Required for global hotkeys from any app.\nSystem Settings → Privacy & Security → Accessibility",
                                    granted: coordinator.hotkeyManager.isAccessibilityGranted,
                                    action: { coordinator.hotkeyManager.requestAccessibilityIfNeeded() }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(width: 440, height: 640)
        .onAppear {
            availableDevices = AudioInputDevice.availableDevices()
        }
    }

    // MARK: - Section Builder

    private func settingsSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(1.2)
            content()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
        }
    }

    // MARK: - Hotkey Row

    private func hotkeyRow(
        label: String,
        description: String,
        hotkey: Hotkey,
        isRecording: Binding<Bool>,
        onNew: @escaping (Hotkey) -> Void,
        onReset: @escaping () -> Void,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).settingsLabel()
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.35))
                }
                Spacer()
                HotkeyField(hotkey: hotkey, isRecording: isRecording, onNewHotkey: onNew)
                    .help(helpText)
            }
            HStack {
                Spacer()
                Button("Reset") { onReset() }
                    .buttonStyle(SettingsGhostButtonStyle())
            }
        }
    }

    // MARK: - Permission Row

    private func settingsPermissionRow(
        icon: String, title: String, description: String,
        granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(granted ? Color(hue: 0.38, saturation: 0.7, brightness: 0.7) : .orange)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hue: 0.38, saturation: 0.7, brightness: 0.7))
            } else {
                Button("Enable →") { action() }
                    .buttonStyle(SettingsGhostButtonStyle())
            }
        }
        .accessibilityLabel(granted ? "\(title) permission granted" : "\(title) permission required")
    }
}

// MARK: - HotkeyField

struct HotkeyField: View {
    let hotkey: Hotkey
    @Binding var isRecording: Bool
    var onNewHotkey: (Hotkey) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stopCapture() } else { startCapture() }
        } label: {
            Text(isRecording ? "Press keys…" : hotkey.displayString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(isRecording ? .orange : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.orange.opacity(0.15) : Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(isRecording ? Color.orange.opacity(0.5) : Color.white.opacity(0.15),
                                    lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Recording new hotkey, press keys" : "Hotkey: \(hotkey.displayString). Click to change.")
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode != UInt16(kVK_Escape) else { stopCapture(); return nil }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option)  { mods |= UInt32(optionKey)  }
            if event.modifierFlags.contains(.shift)   { mods |= UInt32(shiftKey)   }
            if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey)     }
            let newHotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            stopCapture()
            onNewHotkey(newHotkey)
            return nil
        }
    }

    private func stopCapture() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Styles

struct SettingsGhostButtonStyle: ButtonStyle {
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

struct CustomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(configuration.isOn
                          ? Color(hue: 0.62, saturation: 0.7, brightness: 0.7)
                          : Color.white.opacity(0.15))
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .offset(x: configuration.isOn ? 9 : -9)
                    .shadow(color: .black.opacity(0.25), radius: 3)
            }
            .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

private extension Text {
    func settingsLabel() -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
    }
}
