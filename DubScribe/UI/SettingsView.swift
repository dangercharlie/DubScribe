import SwiftUI
import Carbon
import AppKit

/// Settings, organised as three tabs with an Advanced disclosure.
///
/// The shape came out of a design pass that asked two questions of every line:
/// does the label already say this, and does the user need to know it *here*?
/// Fourteen pieces of explanatory prose became two, because most of it restated
/// the label directly above it. What survived is what is genuinely
/// non-obvious — the Carbon hotkey note, and the Bluetooth caveat in the mic
/// test — and even those are drafted as briefly as they can be.
///
/// Tabs rather than one long scroll: seven sections in a single column meant
/// the thing you wanted was usually off-screen. Everything is reachable now in
/// at most two clicks, and the window is a third shorter.
struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var isRecordingHold = false
    @State private var isRecordingPush = false
    @State private var hotkeyWarning: String? = nil
    @State private var availableDevices: [AudioInputDevice] = []
    @State private var tab: Tab = .recording
    @State private var advancedExpanded = false

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case recording = "Recording"
        case storage = "Storage"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch tab {
                    case .general:   generalTab
                    case .recording: recordingTab
                    case .storage:   storageTab
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 420, height: 520)
        .onAppear {
            availableDevices = AudioInputDevice.availableDevices()
        }
        .onDisappear {
            coordinator.micTestManager.reset()
            // The preview belongs to this window; it must not outlive it.
            coordinator.endPreviewHUDAppearance()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 12, weight: tab == item ? .medium : .regular))
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tab == item
                                      ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                                      : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue) settings")
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("Startup") {
                row {
                    Text("Launch at login").settingsLabel()
                } trailing: {
                    Toggle("", isOn: Binding(
                        get: { coordinator.loginItemManager.isEnabled },
                        set: { coordinator.loginItemManager.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Launch at login")
                }
            }

            group("Permissions") {
                row {
                    Text("Microphone").settingsLabel()
                } trailing: {
                    // Deliberately not a status readout. When the permission is
                    // granted there is nothing useful to say, so the row only
                    // changes when something is actually wrong.
                    if PermissionHelpers.isMicrophoneAuthorized {
                        Text("Required")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Enable") { PermissionHelpers.openMicrophoneSettings() }
                            .controlSize(.small)
                    }
                }
            }

            group("About") {
                row {
                    Text("Version").settingsLabel()
                } trailing: {
                    Text(appVersionString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                divider
                row {
                    Link(destination: URL(string: "https://ko-fi.com/dangercharlie")!) {
                        Text("Buy Me a Coffee")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Buy Me a Coffee, opens in your browser")
                } trailing: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: - Recording

    private var recordingTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("Shortcuts") {
                hotkeyRow(
                    label: "Hold to record",
                    hotkey: coordinator.settings.holdHotkey,
                    isRecording: $isRecordingHold,
                    onReset: { hotkeyWarning = nil; coordinator.resetHoldHotkey() },
                    onNew: { newKey in
                        if let reason = newKey.rejectionReason {
                            hotkeyWarning = reason
                        } else if newKey == coordinator.settings.pushHotkey {
                            hotkeyWarning = "Hold and Press must be different."
                        } else {
                            hotkeyWarning = nil
                            coordinator.settings.holdHotkey = newKey
                            coordinator.applySettings()
                        }
                    }
                )
                divider
                hotkeyRow(
                    label: "Press to record",
                    hotkey: coordinator.settings.pushHotkey,
                    isRecording: $isRecordingPush,
                    onReset: { hotkeyWarning = nil; coordinator.resetPushHotkey() },
                    onNew: { newKey in
                        if let reason = newKey.rejectionReason {
                            hotkeyWarning = reason
                        } else if newKey == coordinator.settings.holdHotkey {
                            hotkeyWarning = "Press and Hold must be different."
                        } else {
                            hotkeyWarning = nil
                            coordinator.settings.pushHotkey = newKey
                            coordinator.applySettings()
                        }
                    }
                )

                if let warning = hotkeyWarning {
                    divider
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .accessibilityHidden(true)
                        Text(warning)
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
            }

            group("Input") {
                row {
                    Text("Microphone").settingsLabel()
                } trailing: {
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .accessibilityLabel("Microphone")
                    .help("The input device recordings will use.")
                }
            }

            group("Sounds") {
                row {
                    Text("Sound when recording stops").settingsLabel()
                } trailing: {
                    Toggle("", isOn: $coordinator.settings.playSounds)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Sound when recording stops")
                        .onChange(of: coordinator.settings.playSounds) { _ in coordinator.applySettings() }
                }
            }

            advancedGroup
        }
    }

    /// The disclosure leads the group it opens, separated by the same inset rule
    /// as any other row — so it reads as a header and its contents, not as a
    /// button with an unrelated list beneath it.
    private var advancedGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { advancedExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(advancedExpanded ? Color.primary : Color.secondary)
                        .accessibilityHidden(true)
                    Text("Advanced").settingsLabel()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced settings")
            .accessibilityValue(advancedExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows media handling and the level indicator")

            if advancedExpanded {
                divider
                row {
                    Text("Sound when recording starts").settingsLabel()
                } trailing: {
                    Toggle("", isOn: $coordinator.settings.playStartCue)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Sound when recording starts")
                        .help("Capture begins only after the cue finishes, so the cue is never recorded.")
                        .onChange(of: coordinator.settings.playStartCue) { _ in coordinator.applySettings() }
                }

                divider
                row {
                    Text("Mute while recording").settingsLabel()
                } trailing: {
                    Toggle("", isOn: $coordinator.settings.muteSystemAudioDuringRecording)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Mute while recording")
                        .help("Silences your speakers for the duration of a recording, and restores the level afterwards.")
                        .onChange(of: coordinator.settings.muteSystemAudioDuringRecording) { _ in coordinator.applySettings() }
                }

                divider
                row {
                    Text("Level indicator").settingsLabel()
                } trailing: {
                    Toggle("", isOn: $coordinator.settings.showRecordingHUD)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Level indicator")
                        .onChange(of: coordinator.settings.showRecordingHUD) { _ in coordinator.applySettings() }
                }

                if coordinator.settings.showRecordingHUD {
                    divider
                    row {
                        Text("Transparency").settingsLabel()
                    } trailing: {
                        HStack(spacing: 8) {
                            Slider(value: $coordinator.settings.hudOpacity,
                                   in: 0.0...1.0) { editing in
                                // The indicator appears as soon as the slider is
                                // grabbed, so the effect of the drag is visible
                                // while it is being made. Settings save at the end.
                                if editing { coordinator.previewHUDAppearance() }
                                else { coordinator.applySettings() }
                            }
                            .frame(width: 90)
                            .accessibilityLabel("Transparency")
                            .help("How much the desktop shows through the indicator.")
                            Text("\(Int(coordinator.settings.hudOpacity * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .onChange(of: coordinator.settings.hudOpacity) { _ in
                            coordinator.updateHUDAppearance()
                            // Covers the keyboard, where there is no drag to begin.
                            coordinator.previewHUDAppearance()
                        }
                    }
                }

                divider
                micTest
            }
        }
        .background(card)
        .padding(.top, 14)
    }

    // MARK: - Microphone test

    private var micTest: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button(coordinator.micTestManager.state == .idle ? "Start Monitor" : "Stop Monitor") {
                    if coordinator.micTestManager.state == .idle {
                        coordinator.micTestManager.startMonitor()
                    } else if coordinator.micTestManager.state == .monitoring {
                        coordinator.micTestManager.stopMonitor()
                    }
                }
                .controlSize(.small)

                if coordinator.micTestManager.state == .recordingTest {
                    Button("Stop") { coordinator.micTestManager.stopTestRecording() }
                        .controlSize(.small)
                } else if coordinator.micTestManager.state == .testDone || coordinator.micTestManager.state == .playingTest {
                    Button(coordinator.micTestManager.state == .playingTest ? "Playing…" : "Play Test Clip") {
                        coordinator.micTestManager.playTestClip()
                    }
                    .controlSize(.small)
                    .disabled(coordinator.micTestManager.state == .playingTest)
                }
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor)).frame(height: 7)
                    Capsule()
                        .fill(coordinator.micTestManager.crossesThreshold ? Color.green : Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(min(max(coordinator.micTestManager.inputLevel, 0), 1)),
                               height: 7)
                        .animation(.linear(duration: 0.05), value: coordinator.micTestManager.inputLevel)
                    Rectangle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 2, height: 11)
                        .offset(x: geo.size.width * CGFloat(min(max(coordinator.settings.micTestThreshold, 0), 1)) - 1)
                }
            }
            .frame(height: 11)

            if coordinator.micTestManager.state != .idle {
                // Worth stating plainly: this gets reported as the app
                // "hijacking" Bluetooth audio, when it is macOS switching the
                // headset to narrowband call mode while a capture stream is open.
                Text("Bluetooth headsets drop to call quality while monitoring.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Storage

    private var storageTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("Clips") {
                row {
                    Text("Delete clips automatically").settingsLabel()
                } trailing: {
                    Toggle("", isOn: $coordinator.settings.autoDeleteClips)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Delete clips automatically")
                        .help("Moves the oldest clips to the Trash when the folder needs the room. A clip on the clipboard is never deleted.")
                        .onChange(of: coordinator.settings.autoDeleteClips) { _ in
                            coordinator.applySettings()
                            coordinator.clipStore.sweep()
                        }
                }

                if coordinator.settings.autoDeleteClips {
                    divider
                    row {
                        Text("Folder size limit").settingsLabel()
                    } trailing: {
                        HStack(spacing: 8) {
                            Slider(value: $coordinator.settings.maxClipsSizeMB, in: 50...2000, step: 50)
                                .frame(width: 90)
                                .accessibilityLabel("Folder size limit")
                                .accessibilityValue("\(Int(coordinator.settings.maxClipsSizeMB)) megabytes")
                                .help("Oldest clips are removed first once the folder passes this size.")
                                .onChange(of: coordinator.settings.maxClipsSizeMB) { _ in
                                    coordinator.applySettings()
                                    coordinator.clipStore.sweep()
                                }
                            Text("\(Int(coordinator.settings.maxClipsSizeMB)) MB")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .trailing)
                        }
                    }
                }
            }

            group("Location") {
                row {
                    Text("Clips folder").settingsLabel()
                    Spacer(minLength: 0)
                } trailing: {
                    Button("Show in Finder") { coordinator.revealClipsFolder() }
                        .controlSize(.small)
                        .accessibilityLabel("Show clips folder in Finder")
                }
                // The path gets its own full-width line: sharing the row with
                // the button squeezes it into a mid-path wrap.
                Text(FileManagerHelpers.clipsDirectory.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Building blocks

    private var card: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var divider: some View {
        Divider().padding(.leading, 12)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(card)
        }
        .padding(.top, 14)
    }

    private func row<L: View, T: View>(
        @ViewBuilder label: () -> L,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        HStack(spacing: 10) {
            label()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// One shortcut: the key field, and a Reset scoped to that binding alone.
    private func hotkeyRow(
        label: String,
        hotkey: Hotkey,
        isRecording: Binding<Bool>,
        onReset: @escaping () -> Void,
        onNew: @escaping (Hotkey) -> Void
    ) -> some View {
        row {
            Text(label).settingsLabel()
        } trailing: {
            HStack(spacing: 8) {
                HotkeyField(hotkey: hotkey, isRecording: isRecording, onNewHotkey: onNew)
                Button("Reset") { onReset() }
                    .controlSize(.small)
                    .accessibilityLabel("Reset \(label) shortcut")
            }
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
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
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Color.orange : Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .frame(minWidth: 78)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isRecording ? Color.orange : Color(nsColor: .separatorColor),
                                lineWidth: isRecording ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording
                            ? "Recording new shortcut, press keys"
                            : "Shortcut: \(hotkey.displayString). Click to change.")
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

            var keyCode = UInt32(event.keyCode)
            // Carbon distinguishes left/right modifiers; NSEvent does not, and
            // the difference only creates confusing display strings.
            if keyCode == 0x3B || keyCode == 0x3E { keyCode = UInt32(kVK_Control) }
            if keyCode == 0x3A || keyCode == 0x3D { keyCode = UInt32(kVK_Option) }

            let newKey = Hotkey(keyCode: keyCode, modifiers: mods)
            onNewHotkey(newKey)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

// MARK: - Styles

private extension Text {
    func settingsLabel() -> some View {
        self
            .font(.system(size: 13))
            .foregroundStyle(.primary)
    }
}
