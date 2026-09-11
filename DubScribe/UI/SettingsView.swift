import SwiftUI
import Carbon
import AppKit

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var isRecordingHold = false
    @State private var isRecordingPush = false
    @State private var hotkeyWarning: String? = nil
    @State private var availableDevices: [AudioInputDevice] = []

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Divider()

                ScrollView {
                    VStack(spacing: 16) {
                        shortcutsSection
                        audioInputSection
                        behaviorSection

                        MicTestSectionView(
                            micTestManager: coordinator.micTestManager,
                            threshold: $coordinator.settings.micTestThreshold,
                            inputDeviceName: selectedInputName
                        )

                        storageSection
                        generalSection
                        permissionsSection
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
            }
        }
        .frame(width: 460, height: 740)
        .onAppear {
            availableDevices = AudioInputDevice.availableDevices()
        }
        .onDisappear {
            coordinator.micTestManager.reset()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("AppMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            // No in-view title: the window's own title bar carries it now, and
            // a second "Settings" directly beneath it just reads as a duplicate.
            Spacer()

            Button {
                coordinator.applySettings()
                // A window, not a sheet, so close it rather than dismissing a
                // presentation. Escape still works via the keyboard shortcut.
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: - 1. Shortcuts

    private var shortcutsSection: some View {
        settingsSection("Recording Shortcuts") {
            VStack(spacing: 12) {
                if let warning = hotkeyWarning {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(warning)
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.orange)
                }

                hotkeyRow(
                    label: "Hold to Record",
                    description: "Hold to record, release to stop",
                    hotkey: coordinator.settings.holdHotkey,
                    isRecording: $isRecordingHold,
                    onNew: { newKey in
                        // A shortcut with no ⌃/⌥/⌘ would be registered globally
                        // and swallow that key everywhere.
                        if let reason = newKey.rejectionReason {
                            hotkeyWarning = reason
                        } else if newKey == coordinator.settings.pushHotkey {
                            hotkeyWarning = "Hold and Push shortcuts must be different."
                        } else {
                            hotkeyWarning = nil
                            coordinator.settings.holdHotkey = newKey
                            coordinator.applySettings()
                        }
                    },
                    onReset: { hotkeyWarning = nil; coordinator.resetHoldHotkey() },
                    helpText: "Hold this shortcut to record. Release to stop and copy to the clipboard."
                )

                Divider()

                hotkeyRow(
                    label: "Push to Record",
                    description: "Press once to start, again to stop",
                    hotkey: coordinator.settings.pushHotkey,
                    isRecording: $isRecordingPush,
                    onNew: { newKey in
                        if let reason = newKey.rejectionReason {
                            hotkeyWarning = reason
                        } else if newKey == coordinator.settings.holdHotkey {
                            hotkeyWarning = "Push and Hold shortcuts must be different."
                        } else {
                            hotkeyWarning = nil
                            coordinator.settings.pushHotkey = newKey
                            coordinator.applySettings()
                        }
                    },
                    onReset: { hotkeyWarning = nil; coordinator.resetPushHotkey() },
                    helpText: "Press once to start recording, press again to stop."
                )
            }
        }
    }

    // MARK: - 2. Audio Input

    private var audioInputSection: some View {
        settingsSection("Audio Input") {
            VStack(spacing: 10) {
                HStack {
                    Text("Input Source").settingsLabel()
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Audio input source")
                    .help("Select the microphone or audio input device to use for recordings.")
                }

                Divider()

                Toggle(isOn: $coordinator.settings.showRecordingHUD) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show level indicator while recording").settingsLabel()
                        Text("A small floating indicator at the top of the screen, showing the destination app, the live input level and elapsed time.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.showRecordingHUD) { _ in coordinator.applySettings() }

                if coordinator.settings.showRecordingHUD {
                    HStack(spacing: 8) {
                        Text("Opacity")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Slider(value: $coordinator.settings.hudOpacity,
                               in: 0.0...1.0) { editing in
                            // Save once, when the drag ends — but preview live.
                            if !editing { coordinator.applySettings() }
                        }
                        .frame(maxWidth: 150)
                        Text("\(Int(coordinator.settings.hudOpacity * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.leading, 2)
                    .onChange(of: coordinator.settings.hudOpacity) { _ in
                        coordinator.updateHUDAppearance()
                    }
                    .help("How strongly the indicator is frosted. At 100% it is the lightest frost it has ever been — this used to be the most transparent setting — and turning it down fades the frost itself, so the desktop shows through more. The level dots and timer stay fully opaque.")
                }

                Toggle(isOn: $coordinator.settings.playSounds) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Play a sound when recording stops").settingsLabel()
                        Text("Confirms the clip is saved and copied.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.playSounds) { _ in coordinator.applySettings() }

                Toggle(isOn: $coordinator.settings.playStartCue) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Play a sound when recording starts").settingsLabel()
                        Text("Off by default. Useful if you cannot see the level indicator — but note capture begins only after the cue finishes, so the cue is never recorded.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.playStartCue) { _ in coordinator.applySettings() }
            }
        }
    }

    // MARK: - 3. Recording Behavior

    private var behaviorSection: some View {
        settingsSection("Recording Behavior") {
            VStack(spacing: 12) {
                Toggle(isOn: $coordinator.settings.muteSystemAudioDuringRecording) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Mute system audio while recording").settingsLabel()
                        Text("Mutes output on start and restores it on stop.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.muteSystemAudioDuringRecording) { _ in
                    coordinator.applySettings()
                }

                Divider()

                Toggle(isOn: $coordinator.settings.pauseMediaDuringRecording) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pause media playback while recording").settingsLabel()
                        Text("Pauses Spotify, Music, VLC or browser media, then resumes it.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.pauseMediaDuringRecording) { _ in
                    coordinator.applySettings()
                }

                if coordinator.settings.pauseMediaDuringRecording {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Resume delay").settingsLabel()
                            Spacer()
                            Text(String(format: "%.1fs", coordinator.settings.mediaResumeDelay))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.settings.mediaResumeDelay, in: 0.0...1.0, step: 0.1)
                            .onChange(of: coordinator.settings.mediaResumeDelay) { _ in
                                coordinator.applySettings()
                            }
                            .accessibilityLabel("Media resume delay")
                            .accessibilityValue(String(format: "%.1f seconds", coordinator.settings.mediaResumeDelay))
                            .help("How long to wait after stopping before resuming media playback.")
                        Text("Crossover delay before resuming, so the tail of the recording is not overlapped.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 5. Storage / self-delete

    private var storageSection: some View {
        settingsSection("Clip Storage") {
            VStack(spacing: 12) {
                Toggle(isOn: $coordinator.settings.autoDeleteClips) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Automatically delete clips").settingsLabel()
                        Text("Moves a clip to the Trash once it is no longer pasteable.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: coordinator.settings.autoDeleteClips) { _ in
                    coordinator.applySettings()
                    coordinator.clipStore.sweep()
                }

                if coordinator.settings.autoDeleteClips {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Keep for").settingsLabel()
                            Spacer()
                            Text(retentionLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.settings.clipRetentionMinutes, in: 0.5...30, step: 0.5)
                            .onChange(of: coordinator.settings.clipRetentionMinutes) { _ in
                                coordinator.applySettings()
                            }
                            .accessibilityLabel("Clip retention time")
                            .accessibilityValue(retentionLabel)
                            .help("How long a clip stays on disk after it leaves the clipboard.")
                        Text("A clip on the clipboard is never deleted, however old it is.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Limit folder size").settingsLabel()
                            Spacer()
                            Text("\(Int(coordinator.settings.maxClipsSizeMB)) MB")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $coordinator.settings.maxClipsSizeMB, in: 50...2000, step: 50)
                            .onChange(of: coordinator.settings.maxClipsSizeMB) { _ in
                                coordinator.applySettings()
                                coordinator.clipStore.sweep()
                            }
                            .accessibilityLabel("Clips folder size limit")
                            .accessibilityValue("\(Int(coordinator.settings.maxClipsSizeMB)) megabytes")
                            .help("Upper bound on the clips folder. Oldest unprotected clips are removed first.")
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clips folder").settingsLabel()
                        Text(FileManagerHelpers.clipsDirectory.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Text("\(coordinator.clipStore.clipCount) clip\(coordinator.clipStore.clipCount == 1 ? "" : "s") · \(formattedBytes(coordinator.clipStore.totalBytes))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal") { coordinator.revealClipsFolder() }
                        .controlSize(.small)
                        .accessibilityLabel("Reveal clips folder in Finder")
                        .help("Reveal the DubScribe clips folder in Finder")
                }
            }
        }
    }

    /// Human-readable name of the input the mic test will actually use.
    private var selectedInputName: String {
        let id = coordinator.settings.selectedInputDeviceID ?? "system_default"
        return availableDevices.first { $0.id == id }?.name ?? "System Default"
    }

    private var retentionLabel: String {        let m = coordinator.settings.clipRetentionMinutes
        return m < 1
            ? String(format: "%.0f seconds", m * 60)
            : (m == floor(m) ? "\(Int(m)) minutes" : String(format: "%.1f minutes", m))
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb < 1 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }

    // MARK: - 6. General

    private var generalSection: some View {
        settingsSection("General") {
            Toggle(isOn: Binding(
                get: { coordinator.loginItemManager.isEnabled },
                set: { coordinator.loginItemManager.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Launch at login").settingsLabel()
                    Text("Start DubScribe automatically so the shortcut is always available.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - 7. Permissions

    private var permissionsSection: some View {
        settingsSection("Permissions") {
            VStack(spacing: 10) {
                settingsPermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Required to record audio.",
                    granted: PermissionHelpers.isMicrophoneAuthorized,
                    action: { PermissionHelpers.openMicrophoneSettings() }
                )
                settingsPermissionRow(
                    icon: "playpause",
                    title: "Media Keys",
                    description: "Only needed to pause browser or Now Playing audio.",
                    granted: PermissionHelpers.isMediaKeyControlAuthorized,
                    action: {
                        if !PermissionHelpers.requestMediaKeyControlPermission() {
                            PermissionHelpers.openAccessibilitySettings()
                        }
                    }
                )

                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Global Shortcuts")
                            .font(.system(size: 12, weight: .medium))
                        Text("Carbon hotkeys — no Accessibility permission needed.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(coordinator.hotkeyManager.hotkeysRegistered
                             ? "Registered"
                             : "Not registered — try restarting DubScribe")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(coordinator.hotkeyManager.hotkeysRegistered ? Color.green : Color.orange)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - 8. About

    private var aboutSection: some View {
        settingsSection("About") {
            HStack(spacing: 14) {
                // The bundle's app icon — an .appiconset is not reliably
                // reachable through NSImage(named:).
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DubScribe")
                        .font(.system(size: 13, weight: .semibold))
                    Text(appVersionString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Link(destination: URL(string: "https://ko-fi.com/dangercharlie")!) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// Read from the bundle rather than hardcoding, so it can never drift from
    /// the actual build again.
    private var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (build \(build))"
    }

    // MARK: - Section Builder

    private func settingsSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            content()
                .padding(14)
                .background(CardBackground(corner: 12))
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).settingsLabel()
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                HotkeyField(hotkey: hotkey, isRecording: isRecording, onNewHotkey: onNew)
                    .help(helpText)
            }
            HStack {
                Spacer()
                Button("Reset") { onReset() }
                    .controlSize(.small)
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
                .font(.system(size: 14))
                .foregroundStyle(granted ? Color.green : Color.orange)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Button("Enable") { action() }
                    .controlSize(.small)
            }
        }
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
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Color.orange : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 96)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
            let newHotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            stopCapture()
            // Validation lives in Hotkey.rejectionReason, surfaced by the caller
            // as a warning rather than silently arming a dangerous shortcut.
            onNewHotkey(newHotkey)
            return nil
        }
    }

    private func stopCapture() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - Mic Test

struct MicTestSectionView: View {
    @ObservedObject var micTestManager: MicTestManager
    @Binding var threshold: Float
    let inputDeviceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Microphone Test")

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: micTestStatusIcon)
                        .font(.system(size: 13))
                        .foregroundStyle(micTestStatusColor)
                    Text(micTestStatusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(nsColor: .quaternaryLabelColor)).frame(height: 8)
                        Capsule()
                            .fill(micTestManager.crossesThreshold ? Color.green : Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(min(max(micTestManager.inputLevel, 0), 1)),
                                   height: 8)
                            .animation(.linear(duration: 0.05), value: micTestManager.inputLevel)

                        // Level guide
                        Rectangle()
                            .fill(Color.orange.opacity(0.8))
                            .frame(width: 2, height: 12)
                            .offset(x: geo.size.width * CGFloat(min(max(threshold, 0), 1)) - 1)
                    }
                }
                .frame(height: 12)

                HStack(spacing: 8) {
                    Text(String(format: "%.0f%%", micTestManager.inputLevel * 100))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("· guide \(Int(threshold * 100))%")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button(micTestManager.state == .idle ? "Start Monitor" : "Stop Monitor") {
                        if micTestManager.state == .idle {
                            micTestManager.startMonitor()
                        } else if micTestManager.state == .monitoring {
                            micTestManager.stopMonitor()
                        }
                    }
                    .controlSize(.small)

                    if micTestManager.state == .monitoring {
                        Button("Record Test Clip") { micTestManager.startTestRecording() }
                            .controlSize(.small)
                    } else if micTestManager.state == .recordingTest {
                        Button("Stop") { micTestManager.stopTestRecording() }
                            .controlSize(.small)
                    } else if micTestManager.state == .testDone || micTestManager.state == .playingTest {
                        Button(micTestManager.state == .playingTest ? "Playing…" : "Play Test Clip") {
                            micTestManager.playTestClip()
                        }
                        .controlSize(.small)
                        .disabled(micTestManager.state == .playingTest)
                    }

                    Spacer()
                }

                Text("Test clips stay in the system temp folder and are never copied to your clipboard.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Testing: \(inputDeviceName)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    // Worth stating plainly: users reported this as the app
                    // "hijacking" their Bluetooth audio, when it is really macOS
                    // switching the headset to narrowband call mode for as long as
                    // a capture stream is open.
                    Text("While monitoring, macOS switches a Bluetooth headset into its low-quality call mode. It returns to normal when you stop, and DubScribe never holds the microphone open on its own.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(CardBackground(corner: 12))
        }
    }

    private var micTestStatusIcon: String {
        switch micTestManager.state {
        case .idle:          return "mic.slash"
        case .monitoring:    return micTestManager.crossesThreshold ? "waveform" : "ear"
        case .recordingTest: return "mic.fill"
        case .playingTest:   return "play.fill"
        case .testDone:      return "checkmark.circle"
        }
    }

    private var micTestStatusColor: Color {
        switch micTestManager.state {
        case .idle:          return .secondary
        case .monitoring:    return micTestManager.crossesThreshold ? .green : .accentColor
        case .recordingTest: return .red
        case .playingTest:   return .accentColor
        case .testDone:      return .green
        }
    }

    private var micTestStatusText: String {
        switch micTestManager.state {
        case .idle:          return "Start monitoring to check your input level"
        case .monitoring:    return micTestManager.crossesThreshold ? "Voice detected" : "Listening…"
        case .recordingTest: return "Recording test clip…"
        case .playingTest:   return "Playing back test clip…"
        case .testDone:      return "Test clip ready — press Play to listen"
        }
    }
}

// MARK: - Styles

private extension Text {
    func settingsLabel() -> some View {
        self
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
    }
}
