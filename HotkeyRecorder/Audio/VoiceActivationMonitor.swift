import Foundation
import AVFoundation

/// Monitors microphone input level and triggers recording when voice activity
/// crosses a configurable threshold.
@MainActor
final class VoiceActivationMonitor: NSObject, ObservableObject {

    @Published var currentLevel: Float = 0  // 0.0 … 1.0 normalised power

    var onVoiceStarted: (() -> Void)?
    var onVoiceStopped: (() -> Void)?

    private var engine: AVAudioEngine?
    private var isMonitoring = false
    private var isVoiceActive = false
    private var silenceTimer: Timer?

    var threshold: Float = 0.02         // trigger level (0–1)
    var stopDelay: TimeInterval = 1.0   // seconds of silence before stop

    // Safeguards
    private var lastStopTime: Date?
    private let cooldownInterval: TimeInterval = 0.5
    private var isCurrentlyRecording = false // set by coordinator

    // MARK: - Control

    func startMonitoring() {
        guard !isMonitoring else { return }
        setUpEngine()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isMonitoring = false
        isVoiceActive = false
        currentLevel = 0
        cancelSilenceTimer()
    }

    /// Called by coordinator when a recording starts/stops so VA doesn't interfere.
    func setRecordingActive(_ active: Bool) {
        isCurrentlyRecording = active
        if !active {
            lastStopTime = Date()
            isVoiceActive = false
            cancelSilenceTimer()
        }
    }

    // MARK: - Engine

    private func setUpEngine() {
        let eng = AVAudioEngine()
        engine = eng
        let input = eng.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.rmsLevel(buffer: buffer)
            Task { @MainActor in
                self.currentLevel = level
                self.handleLevel(level)
            }
        }

        do {
            try eng.start()
            isMonitoring = true
        } catch {
            print("VoiceActivationMonitor: engine start failed — \(error)")
            engine = nil
        }
    }

    // MARK: - Level Logic

    private func handleLevel(_ level: Float) {
        // Don't interfere with manual/hotkey recording
        guard !isCurrentlyRecording else { return }

        // Respect cooldown between auto recordings
        if let last = lastStopTime, Date().timeIntervalSince(last) < cooldownInterval { return }

        if level >= threshold {
            cancelSilenceTimer()
            if !isVoiceActive {
                isVoiceActive = true
                onVoiceStarted?()
            }
        } else {
            if isVoiceActive && silenceTimer == nil {
                silenceTimer = Timer.scheduledTimer(withTimeInterval: stopDelay, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.isVoiceActive = false
                        self.cancelSilenceTimer()
                        self.onVoiceStopped?()
                    }
                }
            }
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - RMS Helper

    private static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride
        ).map { channelDataValue[$0] }
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(channelDataValueArray.count))
        return min(rms * 10, 1.0) // scale to 0–1 range
    }
}
