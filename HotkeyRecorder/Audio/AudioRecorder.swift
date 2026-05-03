import Foundation
import AVFoundation
import Combine

/// Manages audio recording using AVAudioRecorder.
/// Writes directly to a WAV file using LinearPCM settings.
/// Supports input device selection via AVCaptureDevice / AudioDeviceID.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    private let minimumDuration: TimeInterval = 0.3

    var onRecordingFinished: ((URL?) -> Void)?

    /// The AudioDeviceID (as String) to record from, or nil for system default.
    var selectedInputDeviceID: String?

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
            var settings = WAVExporter.recorderSettings
            let rec = try AVAudioRecorder(url: url, settings: settings)
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
        rec.stop()
        stopDurationTimer()
        recorder = nil
        isRecording = false

        guard let url = currentURL else {
            onRecordingFinished?(nil)
            return
        }
        onRecordingFinished?(url)
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
        Task { @MainActor in self.lastError = msg }
    }
}

// MARK: - Input Device Enumeration

struct AudioInputDevice: Identifiable, Equatable {
    let id: String          // Unique device UID string
    let name: String

    static var systemDefault: AudioInputDevice {
        AudioInputDevice(id: "system_default", name: "System Default")
    }

    static func availableDevices() -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = [.systemDefault]
        // .builtInMicrophone is available on macOS 13; .microphone added in macOS 14
        var deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.microphone)
        }
        // De-duplicate by using a set of UIDs
        var seen = Set<String>()
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )
        for device in discoverySession.devices where seen.insert(device.uniqueID).inserted {
            devices.append(AudioInputDevice(id: device.uniqueID, name: device.localizedName))
        }
        return devices
    }
}
