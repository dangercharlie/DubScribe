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
    @Published var isSettingsOpen = false

    let audioRecorder           = AudioRecorder()
    let audioPlayer             = AudioPlayer()
    let hotkeyManager           = HotkeyManager()
    let loginItemManager        = LoginItemManager()
    let voiceActivationMonitor  = VoiceActivationMonitor()
    let systemMediaController   = SystemMediaController()
    lazy var micTestManager     = MicTestManager(audioRecorder: audioRecorder)

    private var cancellables = Set<AnyCancellable>()
    private var pendingStartTask: Task<Void, Never>?
    private var pendingMediaPauseTask: Task<Void, Never>?

    init() {
        // Wire voice monitor to use the recorder's level
        voiceActivationMonitor.audioRecorder = audioRecorder
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
        hotkeyManager.onHoldKeyDown = { [weak self] in
            self?.startRecording(trigger: .holdHotkey)
        }
        hotkeyManager.onHoldKeyUp = { [weak self] in
            guard self?.recordingState.trigger == .holdHotkey else { return }
            self?.stopRecording()
        }
        hotkeyManager.onPushKeyDown = { [weak self] in
            guard let self else { return }
            if self.recordingState.trigger == .pushHotkey {
                self.stopRecording()
            } else if !self.recordingState.isRecording {
                self.startRecording(trigger: .pushHotkey)
            }
        }
    }

    private func wireVoiceActivation() {
        voiceActivationMonitor.onVoiceStarted = { [weak self] in
            guard let self, !self.recordingState.isRecording else { return }
            if self.isSettingsOpen || self.micTestManager.state != .idle { return }
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

        // Stop mic test if active
        if micTestManager.state != .idle { micTestManager.reset() }

        switch PermissionHelpers.microphoneAuthorizationStatus {
        case .authorized:
            recordingState = .recording(startedAt: Date(), trigger: trigger)
            audioRecorder.selectedInputDeviceID = settings.selectedInputDeviceID
            let shouldMuteSystemAudio = settings.muteSystemAudioDuringRecording
            let shouldPauseMedia = settings.pauseMediaDuringRecording

            pendingStartTask?.cancel()
            pendingMediaPauseTask?.cancel()
            pendingStartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self, !Task.isCancelled, self.recordingState.isRecording else { return }

                // Stop the monitor engine before starting the recording engine
                // to avoid two AVAudioEngines on the same input device.
                // The recording engine's own buffer tap updates inputLevel,
                // so the voice activation monitor can still detect silence.
                self.audioRecorder.stopLevelMonitoring()
                self.audioRecorder.startRecording()
                self.voiceActivationMonitor.setRecordingActive(true)
                self.micTestManager.isRealRecordingActive = true

                self.playSound(named: "Tink")
                print("[DubScribe] Recording started (trigger=\(trigger))")

                if shouldMuteSystemAudio || shouldPauseMedia {
                    self.pendingMediaPauseTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard let self, !Task.isCancelled, self.recordingState.isRecording else { return }
                        if shouldMuteSystemAudio {
                            await self.systemMediaController.muteSystemAudio()
                        }
                        if shouldPauseMedia {
                            await self.systemMediaController.pauseMedia()
                        }
                    }
                }
            }

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
        pendingStartTask?.cancel()
        pendingStartTask = nil
        pendingMediaPauseTask?.cancel()
        pendingMediaPauseTask = nil
        let recorderWasActive = audioRecorder.isRecording
        recordingState = .processing
        lastDuration = audioRecorder.recordingDuration

        guard recorderWasActive else {
            recordingState = .idle
            return
        }

        audioRecorder.stopLevelMonitoring()
        audioRecorder.stopRecording()
        voiceActivationMonitor.setRecordingActive(false)
        micTestManager.isRealRecordingActive = false

        let shouldRestoreSystemAudio = settings.muteSystemAudioDuringRecording
        let shouldResumeMedia = settings.pauseMediaDuringRecording
        if shouldRestoreSystemAudio || shouldResumeMedia {
            let delay = settings.mediaResumeDelay
            let systemMediaController = systemMediaController
            Task {
                if shouldRestoreSystemAudio {
                    await systemMediaController.restoreSystemAudio()
                }
                // Resume media with configurable crossover delay.
                // This is stop-side only; it should not affect recording startup.
                if shouldResumeMedia {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    await systemMediaController.resumeMedia()
                }
            }
        }

        playSound(named: "Pop")
    }

    private func handleRecordingFinished(url: URL?) {
        guard let url else {
            recordingState = .failed(audioRecorder.lastError ?? "Unknown recording error.")
            restoreVoiceState()
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
        restoreVoiceState()
    }

    private func restoreVoiceState() {
        if settings.voiceActivationEnabled {
            // Resume level monitoring for voice activation
            audioRecorder.startLevelMonitoring()
            if !recordingState.isRecording {
                recordingState = .listeningForVoice
            }
        } else if case .listeningForVoice = recordingState {
            recordingState = .idle
        }
    }

    // MARK: - Settings

    func applySettings() {
        settings.save()
        hotkeyManager.configure(holdHotkey: settings.holdHotkey, pushHotkey: settings.pushHotkey)
        voiceActivationMonitor.threshold  = settings.voiceActivationThreshold
        voiceActivationMonitor.stopDelay  = settings.voiceActivationStopDelay
        micTestManager.threshold          = settings.voiceActivationThreshold

        if settings.voiceActivationEnabled {
            audioRecorder.startLevelMonitoring()
            voiceActivationMonitor.startMonitoring()
            if !recordingState.isRecording {
                recordingState = .listeningForVoice
            }
        } else {
            if !recordingState.isRecording {
                audioRecorder.stopLevelMonitoring()
            }
            voiceActivationMonitor.stopMonitoring()
            if case .listeningForVoice = recordingState { recordingState = .idle }
        }
    }

    func resetHoldHotkey() { settings.holdHotkey = .defaultHoldHotkey; applySettings() }
    func resetPushHotkey() { settings.pushHotkey = .defaultPushHotkey; applySettings() }

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

    func revealClipsFolder() { FileManagerHelpers.revealClipsFolder() }

    // MARK: - Permissions

    var allPermissionsGranted: Bool {
        // Carbon hotkeys don't need Accessibility — only mic matters
        PermissionHelpers.isMicrophoneAuthorized
    }
}
