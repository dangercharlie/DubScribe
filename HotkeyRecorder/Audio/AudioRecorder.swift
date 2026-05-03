import Foundation
import AVFoundation
import CoreAudio

/// Records microphone audio to a WAV file using AVAudioEngine + AVAudioFile.
/// AVAudioEngine lets us:
///   • select a specific input device (via AudioUnit property)
///   • meter input levels from the buffer tap
///   • write PCM buffers directly to a WAV file without extra conversion
@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var lastError: String?

    /// Live input level 0…1 (updated ~10× per second while recording or monitoring)
    @Published var inputLevel: Float = 0

    var onRecordingFinished: ((URL?) -> Void)?

    /// UID of the audio device to record from (nil = system default)
    var selectedInputDeviceID: String?

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var peakLevel: Float = 0

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }

        do { try FileManagerHelpers.ensureClipsDirectoryExists() }
        catch {
            fail("Cannot create clips directory: \(error.localizedDescription)")
            return
        }

        let url = FileManagerHelpers.newClipURL()
        currentURL = url

        do {
            let eng = AVAudioEngine()
            engine = eng

            // Route to selected input device if specified
            if let uid = selectedInputDeviceID, uid != "system_default" {
                setInputDevice(uid: uid, on: eng)
            }

            let inputNode = eng.inputNode
            // Use the hardware's native format to avoid sample-rate conversion issues
            let hwFormat = inputNode.inputFormat(forBus: 0)
            print("[DubScribe.Audio] Hardware input format: \(hwFormat)")

            // WAV output settings: 44.1 kHz, 16-bit, mono
            let fileSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: hwFormat.sampleRate,   // match hardware rate
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let af = try AVAudioFile(forWriting: url, settings: fileSettings)
            audioFile = af

            print("[DubScribe.Audio] Recording started → \(url.lastPathComponent)")

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                guard let self, let af = self.audioFile else { return }
                do {
                    // Convert to mono if stereo
                    let monoBuffer = Self.toMono(buffer: buffer)
                    try af.write(from: monoBuffer)
                } catch {
                    print("[DubScribe.Audio] Write error: \(error)")
                }
                // Update level meter
                let level = Self.rmsLevel(buffer: buffer)
                Task { @MainActor in
                    self.inputLevel = level
                    self.peakLevel = max(self.peakLevel, level)
                }
            }

            try eng.start()
            isRecording = true
            recordingStartTime = Date()
            recordingDuration = 0
            peakLevel = 0
            lastError = nil
            startDurationTimer()

        } catch {
            fail("Cannot start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        isRecording = false
        stopDurationTimer()
        inputLevel = 0

        guard let url = currentURL else { onRecordingFinished?(nil); return }
        currentURL = nil

        // Warn if recording appears silent
        if peakLevel < 0.002 {
            print("[DubScribe.Audio] Warning: recording may be silent (peak level \(peakLevel))")
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
            print("[DubScribe.Audio] Finished: duration=\(String(format:"%.2f",recordingDuration))s  size=\(size/1024)KB  file=\(url.lastPathComponent)")
        }
        onRecordingFinished?(url)
    }

    // MARK: - Shared Level Monitoring (without recording)

    private var monitorEngine: AVAudioEngine?

    func startLevelMonitoring() {
        guard monitorEngine == nil, !isRecording else { return }
        let eng = AVAudioEngine()
        monitorEngine = eng
        if let uid = selectedInputDeviceID, uid != "system_default" {
            setInputDevice(uid: uid, on: eng)
        }
        let inputNode = eng.inputNode
        let fmt = inputNode.inputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            let level = Self.rmsLevel(buffer: buffer)
            Task { @MainActor in self?.inputLevel = level }
        }
        do { try eng.start() }
        catch { print("[DubScribe.Audio] Monitor engine failed: \(error)"); monitorEngine = nil }
    }

    func stopLevelMonitoring() {
        monitorEngine?.inputNode.removeTap(onBus: 0)
        monitorEngine?.stop()
        monitorEngine = nil
        inputLevel = 0
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        print("[DubScribe.Audio] Error: \(message)")
        lastError = message
        isRecording = false
        engine?.stop()
        engine = nil
        audioFile = nil
        onRecordingFinished?(nil)
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in self.recordingDuration = Date().timeIntervalSince(start) }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Input Device Selection via Core Audio

    private func setInputDevice(uid: String, on engine: AVAudioEngine) {
        guard let deviceID = CoreAudioHelpers.deviceID(forUID: uid) else {
            print("[DubScribe.Audio] Device '\(uid)' not found, using system default")
            return
        }
        let inputUnit = engine.inputNode.audioUnit!
        var devID = deviceID
        let status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status == noErr {
            print("[DubScribe.Audio] Input device set to '\(uid)' (deviceID=\(deviceID))")
        } else {
            print("[DubScribe.Audio] Failed to set input device (OSStatus \(status)), using system default")
        }
    }

    // MARK: - Signal Processing

    /// Convert stereo/multichannel buffer to mono (average channels)
    private static func toMono(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer {
        guard buffer.format.channelCount > 1,
              let monoFormat = AVAudioFormat(
                commonFormat: buffer.format.commonFormat,
                sampleRate: buffer.format.sampleRate,
                channels: 1,
                interleaved: buffer.format.isInterleaved),
              let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength)
        else { return buffer }

        mono.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = mono.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            let frameCount = Int(buffer.frameLength)
            for frame in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<channelCount { sum += src[ch][frame] }
                dst[0][frame] = sum / Float(channelCount)
            }
        }
        return mono
    }

    static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let frames = Int(buffer.frameLength)
        let step = buffer.stride
        var sum: Float = 0
        for i in stride(from: 0, to: frames, by: step) { sum += data[0][i] * data[0][i] }
        let rms = sqrt(sum / Float(frames / max(step, 1)))
        return min(rms * 8, 1.0)
    }
}

// MARK: - Input Device Enumeration

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String

    static var systemDefault: AudioInputDevice {
        AudioInputDevice(id: "system_default", name: "System Default")
    }

    static func availableDevices() -> [AudioInputDevice] {
        var list: [AudioInputDevice] = [.systemDefault]
        for dev in CoreAudioHelpers.inputDevices() {
            list.append(AudioInputDevice(id: dev.uid, name: dev.name))
        }
        return list
    }
}

// MARK: - Core Audio Helpers

enum CoreAudioHelpers {
    struct DeviceInfo { let id: AudioDeviceID; let name: String; let uid: String }

    static func inputDevices() -> [DeviceInfo] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            // Check has input streams
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }
            guard let name = stringProperty(id, kAudioObjectPropertyName),
                  let uid  = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return DeviceInfo(id: id, name: name, uid: uid)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first(where: { $0.uid == uid })?.id
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfStr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr) == noErr else { return nil }
        return cfStr as String?
    }
}
