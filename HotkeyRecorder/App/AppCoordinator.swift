import Foundation
import Combine
import AVFoundation
import AppKit

/// Central coordinator — owns audio, hotkeys, clipboard, playback, voice activation.
@MainActor
final class AppCoordinator: ObservableObject {

    @Published var recordingState: RecordingState = .idle
    @Published var settings: AppSettings = .load()
    @Published var lastClipURL: URL?
    @Published var lastDuration: TimeInterval = 0

    let audioRecorder        = AudioRecorder()
    let audioPlayer          = AudioPlayer()
    let hotkeyManager        = HotkeyManager()
    let loginItemManager     = LoginItemManager()
    let voiceActivationMonitor = VoiceActivationMonitor()

    private var cancellables = Set<AnyCancellable>()

    init() {
        wireAudio()
        wireHotkeys()
        wireVoiceActivation()
        applySettings()
    }

    // MARK: - Wiring

    private func wireAudio() {
        audioRecorder.onRecordingFinished = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in self.handleRecordingFinished(url: url) }
        }
    }

    private func wireHotkeys() {
        // Hold-to-record
        hotkeyManager.onHoldKeyDown = { [weak self] in
            self?.startRecording(trigger: .holdHotkey)
        }
        hotkeyManager.onHoldKeyUp = { [weak self] in
            guard self?.recordingState.trigger == .holdHotkey else { return }
            self?.stopRecording()
        }
        // Push-to-record (toggle)
        hotkeyManager.onPushKeyDown = { [weak self] in
            guard let self else { return }
            if self.recordingState.trigger == .pushHotkey {
                self.stopRecording()
            } else if !self.recordingState.isRecording {
                self.startRecording(trigger: .pushHotkey)
            }
            // Ignore push key if hold-recording is active
        }
    }

    private func wireVoiceActivation() {
        voiceActivationMonitor.onVoiceStarted = { [weak self] in
            guard let self, !self.recordingState.isRecording else { return }
            self.startRecording(trigger: .voiceActivation)
        }
        voiceActivationMonitor.onVoiceStopped = { [weak self] in
            guard let self, self.recordingState.trigger == .voiceActivation else { return }
            self.stopRecording()
        }
    }

    // MARK: - Recording Control

    func startRecording(trigger: RecordingTrigger = .manual) {
        guard !recordingState.isRecording else { return }

        switch PermissionHelpers.microphoneAuthorizationStatus {
        case .authorized:
            recordingState = .recording(startedAt: Date(), trigger: trigger)
            audioRecorder.selectedInputDeviceID = settings.selectedInputDeviceID
            audioRecorder.startRecording()
            voiceActivationMonitor.setRecordingActive(true)
            playSound(named: "Tink")

        case .notDetermined:
            PermissionHelpers.requestMicrophonePermission { [weak self] granted in
                if granted { self?.startRecording(trigger: trigger) }
                else { self?.recordingState = .failed("Microphone access denied.") }
            }

        default:
            recordingState = .failed("Microphone access denied. Enable in System Settings → Privacy & Security → Microphone.")
        }
    }

    func stopRecording() {
        guard recordingState.isRecording else { return }
        recordingState = .processing
        lastDuration = audioRecorder.recordingDuration
        audioRecorder.stopRecording()
        voiceActivationMonitor.setRecordingActive(false)
        playSound(named: "Pop")
    }

    private func handleRecordingFinished(url: URL?) {
        guard let url else {
            recordingState = .failed(audioRecorder.lastError ?? "Unknown recording error.")
            // If voice activation is on, go back to listening state
            updateVoiceActivationState()
            return
        }

        let success = ClipboardManager.copyWAVFile(url)
        if success {
            lastClipURL = url
            recordingState = .copied(url)
            audioPlayer.load(url: url)
        } else {
            recordingState = .failed("Could not copy file to clipboard.")
        }
        updateVoiceActivationState()
    }

    // MARK: - Voice Activation

    private func updateVoiceActivationState() {
        if settings.voiceActivationEnabled {
            if !recordingState.isRecording {
                recordingState = .listeningForVoice
            }
        } else {
            if case .listeningForVoice = recordingState {
                recordingState = .idle
            }
        }
    }

    // MARK: - Settings

    func applySettings() {
        settings.save()
        hotkeyManager.configure(
            holdHotkey: settings.holdHotkey,
            pushHotkey: settings.pushHotkey
        )
        voiceActivationMonitor.threshold  = settings.voiceActivationThreshold
        voiceActivationMonitor.stopDelay  = settings.voiceActivationStopDelay

        if settings.voiceActivationEnabled {
            voiceActivationMonitor.startMonitoring()
            if !recordingState.isRecording {
                recordingState = .listeningForVoice
            }
        } else {
            voiceActivationMonitor.stopMonitoring()
            if case .listeningForVoice = recordingState {
                recordingState = .idle
            }
        }
    }

    func resetHoldHotkey() {
        settings.holdHotkey = .defaultHoldHotkey
        applySettings()
    }

    func resetPushHotkey() {
        settings.pushHotkey = .defaultPushHotkey
        applySettings()
    }

    // MARK: - Sounds

    private func playSound(named name: String) {
        guard settings.playSounds else { return }
        NSSound(named: name)?.play()
    }

    // MARK: - Reveal

    func revealLastClip() {
        guard let url = lastClipURL else { return }
        FileManagerHelpers.revealInFinder(url)
    }

    func revealClipsFolder() {
        FileManagerHelpers.revealClipsFolder()
    }

    // MARK: - Permissions convenience

    var allPermissionsGranted: Bool {
        PermissionHelpers.isMicrophoneAuthorized && hotkeyManager.isAccessibilityGranted
    }
}
