import Foundation
import Combine
import AVFoundation
import AppKit

/// Central coordinator — owns audio, hotkey, clipboard, and state.
@MainActor
final class AppCoordinator: ObservableObject {

    @Published var recordingState: RecordingState = .idle
    @Published var settings: AppSettings = .load()
    @Published var lastClipURL: URL?
    @Published var lastDuration: TimeInterval = 0

    let audioRecorder = AudioRecorder()
    let hotkeyManager = HotkeyManager()
    let loginItemManager = LoginItemManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        wireAudio()
        wireHotkey()
        hotkeyManager.configure(hotkey: settings.hotkey)
    }

    // MARK: - Wiring

    private func wireAudio() {
        audioRecorder.onRecordingFinished = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecordingFinished(url: url)
            }
        }
    }

    private func wireHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            self?.startRecording()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.stopRecording()
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !recordingState.isRecording else { return }

        switch PermissionHelpers.microphoneAuthorizationStatus {
        case .authorized:
            recordingState = .recording(startedAt: Date())
            audioRecorder.startRecording()
            playSound(named: "Tink")

        case .notDetermined:
            PermissionHelpers.requestMicrophonePermission { [weak self] granted in
                if granted { self?.startRecording() }
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
        playSound(named: "Pop")
    }

    private func handleRecordingFinished(url: URL?) {
        guard let url else {
            recordingState = .failed(audioRecorder.lastError ?? "Unknown recording error.")
            return
        }

        let success = ClipboardManager.copyWAVFile(url)
        if success {
            lastClipURL = url
            recordingState = .copied(url)
        } else {
            recordingState = .failed("Could not copy file to clipboard.")
        }
    }

    // MARK: - Settings

    func applySettings() {
        settings.save()
        hotkeyManager.configure(hotkey: settings.hotkey)
    }

    func resetHotkey() {
        settings.hotkey = .defaultHotkey
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
}
