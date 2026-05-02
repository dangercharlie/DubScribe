import SwiftUI
import Carbon

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var isRecordingHotkey = false
    @State private var tempHotkey: Hotkey = .defaultHotkey

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: 0.62, saturation: 0.85, brightness: 0.12),
                    Color(hue: 0.68, saturation: 0.90, brightness: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        coordinator.applySettings()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().background(Color.white.opacity(0.08))

                ScrollView {
                    VStack(spacing: 16) {
                        // Hotkey section
                        settingsSection("Hotkey") {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Global Hotkey")
                                        .settingsLabel()
                                    Spacer()
                                    HotkeyField(
                                        hotkey: coordinator.settings.hotkey,
                                        isRecording: $isRecordingHotkey
                                    ) { newHotkey in
                                        coordinator.settings.hotkey = newHotkey
                                        coordinator.applySettings()
                                    }
                                }

                                HStack {
                                    Spacer()
                                    Button("Reset to Default") {
                                        coordinator.resetHotkey()
                                    }
                                    .buttonStyle(GhostSettingsButtonStyle())
                                }
                            }
                        }

                        // Audio section
                        settingsSection("Audio") {
                            Toggle(isOn: $coordinator.settings.playSounds) {
                                Text("Play sounds on record/stop")
                                    .settingsLabel()
                            }
                            .toggleStyle(CustomToggleStyle())
                            .onChange(of: coordinator.settings.playSounds) { _ in
                                coordinator.applySettings()
                            }
                        }

                        // General section
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

                                Divider().background(Color.white.opacity(0.06))

                                HStack {
                                    Text("Clips Folder")
                                        .settingsLabel()
                                    Spacer()
                                    Button("Reveal") {
                                        coordinator.revealClipsFolder()
                                    }
                                    .buttonStyle(GhostSettingsButtonStyle())
                                }

                                HStack {
                                    Text(FileManagerHelpers.clipsDirectory.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                        .lineLimit(2)
                                    Spacer()
                                }
                            }
                        }

                        // Permissions section
                        settingsSection("Permissions") {
                            VStack(spacing: 10) {
                                permissionRow(
                                    icon: "mic.fill",
                                    title: "Microphone",
                                    description: "Required for recording audio.",
                                    granted: PermissionHelpers.isMicrophoneAuthorized,
                                    action: { PermissionHelpers.openMicrophoneSettings() }
                                )
                                permissionRow(
                                    icon: "keyboard",
                                    title: "Accessibility",
                                    description: "Required for the global hotkey to work from any app.",
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
        .frame(width: 420, height: 560)
        .onAppear {
            tempHotkey = coordinator.settings.hotkey
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
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

    // MARK: - Permission Row

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(granted ? Color(hue: 0.38, saturation: 0.7, brightness: 0.7) : .orange)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hue: 0.38, saturation: 0.7, brightness: 0.7))
            } else {
                Button("Enable →") { action() }
                    .buttonStyle(GhostSettingsButtonStyle())
            }
        }
    }
}

// MARK: - Hotkey Recorder Field

struct HotkeyField: View {
    let hotkey: Hotkey
    @Binding var isRecording: Bool
    var onNewHotkey: (Hotkey) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Text(isRecording ? "Press keys…" : hotkey.displayString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(isRecording ? .orange : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording
                              ? Color.orange.opacity(0.15)
                              : Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(isRecording
                                    ? Color.orange.opacity(0.5)
                                    : Color.white.opacity(0.15),
                                    lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode != UInt16(kVK_Escape) else {
                stopRecording()
                return nil
            }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option)  { mods |= UInt32(optionKey)  }
            if event.modifierFlags.contains(.shift)   { mods |= UInt32(shiftKey)   }
            if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey)     }
            let newHotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            stopRecording()
            onNewHotkey(newHotkey)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// MARK: - Button / Toggle Styles

private struct GhostSettingsButtonStyle: ButtonStyle {
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

private struct CustomToggleStyle: ToggleStyle {
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
