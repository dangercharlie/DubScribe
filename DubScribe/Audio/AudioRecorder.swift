import Foundation
import AVFoundation
import CoreAudio
import QuartzCore

/// Records microphone audio to a WAV file using AVAudioEngine + AVAudioFile.
/// AVAudioEngine lets us:
///   • select a specific input device (via AudioUnit property)
///   • meter input levels from the buffer tap
///   • write PCM buffers directly to a WAV file without extra conversion
@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var lastError: String?

    /// How long the current recording has been running.
    ///
    /// Computed from the start date rather than republished. It used to be a
    /// `@Published` value driven by a 0.1 s timer, which made every observer of
    /// the recorder — the indicator above all — re-evaluate ten times a second
    /// for a figure nothing displayed to better than a second. The indicator
    /// now keeps its own one-second clock from `recordingStartedAt`, and the
    /// coordinator reads this once, at stop, before the engine is torn down.
    var recordingDuration: TimeInterval {
        recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    /// When the current recording began; nil when idle.
    private(set) var recordingStartedAt: Date?

    /// Live input level 0…1 (updated ~10× per second while recording or monitoring).
    ///
    /// Derived from the same capture tap that writes the file, so the level
    /// display never opens a second audio engine — doing so would re-trigger the
    /// Bluetooth call-mode switch that 0.7.0 removed.
    @Published var inputLevel: Float = 0

    /// Rolling level history driving the on-screen dot matrix.
    ///
    /// Filled from the same capture tap that writes the file, so the indicator
    /// never opens a second audio engine — doing so would re-trigger the
    /// Bluetooth call-mode switch that 0.7.0 removed.
    ///
    /// A separate object rather than published properties here, so that the
    /// matrix is the only view invalidated when a buffer lands. See
    /// `WaveformTrace`.
    let trace = WaveformTrace()

    /// Target bins per second.
    ///
    /// The tap's buffer size is NOT controllable. `installTap(bufferSize:)` is
    /// only a hint, and this hardware was measured delivering 100 ms buffers
    /// (4410 frames at 44.1 kHz, 4800 at 48 kHz) for every requested size up to
    /// 4096, so asking for a smaller buffer achieves nothing. Bins are derived
    /// from the buffer duration instead, to hold this rate steady. The buffers
    /// are 100 ms long but do not *arrive* every 100 ms — see `bufferEnd`.
    private static let targetBinsPerSecond: Double = 60

    /// Peak level observed during the most recently finished recording.
    /// Used to discard clips that captured nothing but silence.
    @Published private(set) var lastPeakLevel: Float = 0

    var onRecordingFinished: ((URL?) -> Void)?

    /// UID of the audio device to record from (nil = system default)
    var selectedInputDeviceID: String?

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
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

            // WAV output: 16-bit mono at the hardware's native rate, to avoid
            // resampling artefacts. (Sample rate is NOT fixed at 44.1 kHz.)
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

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, when in
                guard let self, let af = self.audioFile else { return }
                do {
                    // Convert to mono if stereo
                    let monoBuffer = Self.toMono(buffer: buffer)
                    try af.write(from: monoBuffer)
                } catch {
                    print("[DubScribe.Audio] Write error: \(error)")
                }
                // Level and matrix bins, taken from the buffer being written — no
                // second engine and no extra capture. The bin count is derived
                // from the buffer's duration so the matrix's time base stays
                // constant even though the tap delivers ~100 ms buffers at ~10 Hz.
                let level = Self.rmsLevel(buffer: buffer)
                let bufferDuration = Double(buffer.frameLength) / hwFormat.sampleRate
                let binCount = max(1, Int((bufferDuration * Self.targetBinsPerSecond).rounded()))
                let bins = Self.rmsBins(buffer: buffer, count: binCount)
                let stamp = Self.bufferEnd(when, bufferDuration: bufferDuration)
                Task { @MainActor in
                    self.inputLevel = level
                    self.peakLevel = max(self.peakLevel, level)
                    if self.trace.snapshot.bins.isEmpty {
                        // Once per recording, so a device that does not stamp its
                        // buffers (the fallback below) can be recognised in a log.
                        print(String(format: "[DubScribe.Audio] Trace clock: %@ (%ld-frame buffers, newest bin %.1f ms old at delivery)",
                                     stamp.hostClock ? "audio host time" : "wall clock — host time unavailable",
                                     Int(buffer.frameLength), stamp.delay * 1000))
                    }
                    self.trace.append(bins, end: stamp.end,
                                      interval: bufferDuration / Double(bins.count))
                }
            }

            try eng.start()
            isRecording = true
            recordingStartedAt = Date()
            peakLevel = 0
            inputLevel = 0
            trace.reset()
            lastError = nil

        } catch {
            fail("Cannot start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        let duration = recordingDuration
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        isRecording = false
        recordingStartedAt = nil
        inputLevel = 0

        guard let url = currentURL else { onRecordingFinished?(nil); return }
        currentURL = nil

        // Record the peak for this take, then warn if it looks silent.
        lastPeakLevel = peakLevel
        if peakLevel < 0.002 {
            print("[DubScribe.Audio] Warning: recording may be silent (peak level \(peakLevel))")
        }
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
            print("[DubScribe.Audio] Finished: duration=\(String(format:"%.2f",duration))s  size=\(size/1024)KB  file=\(url.lastPathComponent)")
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
        recordingStartedAt = nil
        engine?.stop()
        engine = nil
        audioFile = nil

        // A failed start can leave a zero-length or partial WAV behind. It will
        // never reach the clipboard, so remove it rather than let the clips
        // folder accumulate junk that retention then has to reason about.
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
            currentURL = nil
        }

        onRecordingFinished?(nil)
    }

    /// When the last sample of a tapped buffer was captured, on the reference
    /// clock the indicator draws against.
    ///
    /// Buffers used to be stamped with `Date()` as the tap closure ran, and that
    /// put the tap's scheduling jitter straight into the picture. The callback
    /// does not arrive every 100 ms: the audio HAL hands the engine 512-frame
    /// cycles, a 100 ms buffer is not a whole number of them, and so successive
    /// callbacks alternate between nine and ten cycles apart — measured at
    /// 96 and 107 ms on the built-in microphone at 48 kHz. The indicator derives
    /// every column's position from the newest stamp, so a callback 7 ms late
    /// shifted the entire trace 1.3 pt one way and the next, 4 ms early, shifted
    /// it 0.8 pt back: a visible hitch ten times a second, at any frame rate.
    ///
    /// The audio clock has none of that. `hostTime` is when the buffer's first
    /// sample was captured, and consecutive buffers abut to within a
    /// microsecond. It is converted to `Date`'s clock through an offset sampled
    /// at one instant, so the delivery delay cancels out of the result. Nothing
    /// already on screen then moves except by scrolling; a late callback only
    /// means its newest columns appear a few milliseconds late, in the right
    /// place.
    private static func bufferEnd(_ when: AVAudioTime, bufferDuration: TimeInterval)
        -> (end: TimeInterval, hostClock: Bool, delay: TimeInterval)
    {
        let dateNow = Date().timeIntervalSinceReferenceDate
        // Fallback for a device whose buffers carry no host timestamp. Not seen
        // on anything tested, but the API allows it.
        guard when.isHostTimeValid else { return (dateNow, false, 0) }
        // `CACurrentMediaTime` is `mach_absolute_time` in seconds — the same
        // clock `hostTime` is expressed in.
        let hostNow = CACurrentMediaTime()
        let hostEnd = AVAudioTime.seconds(forHostTime: when.hostTime) + bufferDuration
        let delay = hostNow - hostEnd
        return (dateNow - delay, true, delay)
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

    /// Split a buffer into `count` windows and return the display-scaled RMS of
    /// each, matching the scaling `rmsLevel` uses so the matrix and the level
    /// meter agree.
    static func rmsBins(buffer: AVAudioPCMBuffer, count: Int) -> [Float] {
        guard let data = buffer.floatChannelData, count > 0 else { return [] }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        let step = max(buffer.stride, 1)

        var bins = [Float](repeating: 0, count: count)
        let window = max(1, frames / count)
        for bin in 0..<count {
            let start = bin * window
            let end = min(start + window, frames)
            guard start < end else { continue }
            var sum: Float = 0
            for i in stride(from: start, to: end, by: step) { sum += data[0][i] * data[0][i] }
            let samples = Float(max((end - start) / step, 1))
            bins[bin] = min(sqrt(sum / samples) * 8, 1.0)
        }
        return bins
    }
}

/// The level history behind the indicator's dot matrix, published as one value.
///
/// Kept apart from `AudioRecorder` so the recorder's other observers are left
/// alone when audio arrives, and so the matrix is the only view invalidated by
/// it. The three values used to be three separate published properties on the
/// recorder; publishing them as one struct also means a frame can never see a
/// new end time against the old bins.
@MainActor
final class WaveformTrace: ObservableObject {
    struct Snapshot {
        /// Amplitude per bin, oldest first.
        var bins: [Float] = []
        /// Reference-clock time at which the newest bin ended. The indicator
        /// places every column by time rather than by array index — see
        /// `DotMatrixGeometry` — and this, with `interval`, is what it needs.
        var end: TimeInterval = 0
        /// Spacing between bins, assumed steady across the history. The tap
        /// delivers a constant buffer size, so it is.
        var interval: TimeInterval = 0.02
    }

    @Published private(set) var snapshot = Snapshot()

    /// How many bins are retained — comfortably more than one window's worth.
    static let capacity = 160

    /// Append a buffer's bins, discarding the oldest beyond `capacity`.
    func append(_ bins: [Float], end: TimeInterval, interval: TimeInterval) {
        guard !bins.isEmpty else { return }
        var next = snapshot
        next.bins.append(contentsOf: bins)
        let overflow = next.bins.count - Self.capacity
        if overflow > 0 { next.bins.removeFirst(overflow) }
        next.end = end
        next.interval = interval
        snapshot = next
    }

    func reset() {
        snapshot = Snapshot()
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
        // `kAudioObjectPropertyName` and `kAudioDevicePropertyDeviceUID` both hand
        // back a +1 retained CFString, so it has to be received as `Unmanaged` and
        // released via `takeRetainedValue()`.
        //
        // This previously passed `&cfStr` where `cfStr` was a `CFString?`, which
        // gives CoreAudio the address of a *boxed Optional* rather than of the
        // reference itself. It happened to work because the box is one word wide,
        // but the compiler flags it at higher optimisation and it was never safe.
        var cfStr: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr) == noErr,
              let value = cfStr else { return nil }
        return value.takeRetainedValue() as String
    }
}
