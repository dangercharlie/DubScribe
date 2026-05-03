import Foundation
import AVFoundation

/// Watches the AudioRecorder's live inputLevel and triggers voice-activation
/// recording. This avoids running a second AVAudioEngine which could conflict
/// with the recorder's engine on the same input device.
@MainActor
final class VoiceActivationMonitor: ObservableObject {

    var onVoiceStarted: (() -> Void)?
    var onVoiceStopped: (() -> Void)?

    var threshold: Float = 0.02
    var stopDelay: TimeInterval = 1.0

    private var isVoiceActive = false
    private var silenceTimer: Timer?
    private var isCurrentlyRecording = false
    private var lastStopTime: Date?
    private let cooldown: TimeInterval = 0.5
    private var levelCheckTimer: Timer?

    // Weak reference to the recorder so we can read its inputLevel
    weak var audioRecorder: AudioRecorder?

    func startMonitoring() {
        guard levelCheckTimer == nil else { return }
        levelCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder else { return }
            Task { @MainActor in self.handleLevel(recorder.inputLevel) }
        }
        print("[DubScribe.VoiceActivation] Started monitoring (threshold=\(threshold))")
    }

    func stopMonitoring() {
        levelCheckTimer?.invalidate()
        levelCheckTimer = nil
        isVoiceActive = false
        cancelSilenceTimer()
        print("[DubScribe.VoiceActivation] Stopped monitoring")
    }

    func setRecordingActive(_ active: Bool) {
        isCurrentlyRecording = active
        if !active {
            lastStopTime = Date()
            isVoiceActive = false
            cancelSilenceTimer()
        }
    }

    private func handleLevel(_ level: Float) {
        guard !isCurrentlyRecording else { return }
        if let last = lastStopTime, Date().timeIntervalSince(last) < cooldown { return }

        if level >= threshold {
            cancelSilenceTimer()
            if !isVoiceActive {
                isVoiceActive = true
                print("[DubScribe.VoiceActivation] Voice detected (level=\(String(format:"%.3f",level)) threshold=\(threshold))")
                onVoiceStarted?()
            }
        } else if isVoiceActive && silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: stopDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.isVoiceActive = false
                    self?.cancelSilenceTimer()
                    self?.onVoiceStopped?()
                }
            }
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
