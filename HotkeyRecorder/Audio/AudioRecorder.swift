import Foundation
import AVFoundation
import Combine

/// Manages audio recording using AVAudioRecorder.
/// Writes directly to a WAV file using LinearPCM settings.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    // Minimum clip duration in seconds; shorter clips are still saved but flagged.
    private let minimumDuration: TimeInterval = 0.3

    // Completion: called with the file URL on success, nil on failure.
    var onRecordingFinished: ((URL?) -> Void)?

    // MARK: - Start / Stop

    func startRecording() {
        guard !isRecording else { return }

        do {
            try FileManagerHelpers.ensureClipsDirectoryExists()
        } catch {
            lastError = "Cannot create clips directory: \(error.localizedDescription)"
            onRecordingFinished?(nil)
            return
        }

        let url = FileManagerHelpers.newClipURL()
        currentURL = url

        do {
            let rec = try AVAudioRecorder(url: url, settings: WAVExporter.recorderSettings)
            rec.delegate = self
            rec.prepareToRecord()
            let started = rec.record()
            if !started {
                lastError = "AVAudioRecorder failed to start."
                onRecordingFinished?(nil)
                return
            }
            recorder = rec
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            lastError = nil
            startDurationTimer()
        } catch {
            lastError = "Cannot start recording: \(error.localizedDescription)"
            onRecordingFinished?(nil)
        }
    }

    func stopRecording() {
        guard isRecording, let rec = recorder else { return }

        let elapsed = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        rec.stop()
        stopDurationTimer()
        recorder = nil
        isRecording = false

        guard let url = currentURL else {
            onRecordingFinished?(nil)
            return
        }

        if elapsed < minimumDuration {
            // Still pass the URL — the caller decides how to handle very short clips.
            onRecordingFinished?(url)
        } else {
            onRecordingFinished?(url)
        }
        currentURL = nil
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.lastError = "Recording did not finish successfully."
                self.onRecordingFinished?(nil)
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let msg = error?.localizedDescription ?? "Unknown encoding error"
        Task { @MainActor in
            self.lastError = msg
        }
    }
}
