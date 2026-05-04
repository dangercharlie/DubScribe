import Foundation
import AVFoundation

/// Manages microphone test mode: live level metering + short test clip recording/playback.
/// Uses the same AudioRecorder pipeline so it validates the same input path.
/// Test clips are NEVER copied to clipboard and do NOT replace the last real recording.
@MainActor
final class MicTestManager: ObservableObject {

    enum TestState: Equatable {
        case idle
        case monitoring          // live meter, no recording
        case recordingTest       // recording a short test clip
        case playingTest         // playing back test clip
        case testDone            // clip recorded, ready to play
    }

    @Published var state: TestState = .idle
    @Published var inputLevel: Float = 0   // 0…1 from recorder
    @Published var crossesThreshold = false

    /// Set by coordinator — mic test pauses if a real recording starts
    var isRealRecordingActive = false

    var threshold: Float = 0.02

    private weak var audioRecorder: AudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var testClipURL: URL?
    private var levelTimer: Timer?
    private var recordingTimer: Timer?

    private let maxTestDuration: TimeInterval = 4.0

    init(audioRecorder: AudioRecorder) {
        self.audioRecorder = audioRecorder
    }

    // MARK: - Live Monitor

    func startMonitor() {
        guard state == .idle, !isRealRecordingActive else { return }
        audioRecorder?.startLevelMonitoring()
        state = .monitoring
        startLevelTimer()
        print("[DubScribe.MicTest] Live monitor started")
    }

    func stopMonitor() {
        guard state == .monitoring else { return }
        audioRecorder?.stopLevelMonitoring()
        stopLevelTimer()
        state = .idle
        inputLevel = 0
    }

    // MARK: - Test Clip

    func startTestRecording() {
        guard state == .monitoring, !isRealRecordingActive else { return }

        // Stop level monitor (engine will be replaced by recording engine)
        audioRecorder?.stopLevelMonitoring()

        // Save to a temp location (not the clips folder)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dubscribe_test_\(Int(Date().timeIntervalSince1970)).wav")
        testClipURL = tmp

        // Use the recorder but override the output URL via a temp recording
        // We reuse AudioRecorder.startRecording() but intercept the result
        startLevelTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: maxTestDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopTestRecording() }
        }

        // Directly start a private engine recording to temp URL
        startPrivateRecording(to: tmp)
        state = .recordingTest
        print("[DubScribe.MicTest] Test clip recording started → \(tmp.lastPathComponent)")
    }

    func stopTestRecording() {
        guard state == .recordingTest else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopPrivateRecording()
        state = testClipURL != nil ? .testDone : .idle
        stopLevelTimer()
        // Restart level monitor
        audioRecorder?.startLevelMonitoring()
        startLevelTimer()
        print("[DubScribe.MicTest] Test clip recording stopped")
    }

    func playTestClip() {
        guard state == .testDone, let url = testClipURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            audioPlayer = player
            state = .playingTest
            // Return to testDone when finished
            Timer.scheduledTimer(withTimeInterval: player.duration + 0.3, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    if self?.state == .playingTest { self?.state = .testDone }
                }
            }
            print("[DubScribe.MicTest] Playing test clip (duration=\(String(format:"%.2f",player.duration))s)")
        } catch {
            print("[DubScribe.MicTest] Playback error: \(error)")
        }
    }

    func reset() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopPrivateRecording()
        audioRecorder?.stopLevelMonitoring()
        stopLevelTimer()
        recordingTimer?.invalidate()
        recordingTimer = nil
        state = .idle
        inputLevel = 0
    }

    // MARK: - Private Engine for Test Recording

    private var testEngine: AVAudioEngine?
    private var testFile: AVAudioFile?

    private func startPrivateRecording(to url: URL) {
        let eng = AVAudioEngine()
        testEngine = eng
        let inputNode = eng.inputNode
        let fmt = inputNode.inputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: fmt.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            testFile = file
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
                try? file.write(from: buffer)
                let level = AudioRecorder.rmsLevel(buffer: buffer)
                Task { @MainActor in self?.inputLevel = level }
            }
            try eng.start()
        } catch {
            print("[DubScribe.MicTest] Private engine error: \(error)")
            testEngine = nil
            testFile = nil
        }
    }

    private func stopPrivateRecording() {
        testEngine?.inputNode.removeTap(onBus: 0)
        testEngine?.stop()
        testEngine = nil
        testFile = nil
    }

    // MARK: - Level Timer

    private func startLevelTimer() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // When monitoring (no private engine), read from audioRecorder
                if self.state == .monitoring {
                    self.inputLevel = self.audioRecorder?.inputLevel ?? 0
                }
                self.crossesThreshold = self.inputLevel >= self.threshold
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
