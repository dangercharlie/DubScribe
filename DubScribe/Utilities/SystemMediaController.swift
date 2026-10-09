import Foundation
import CoreAudio
import AudioToolbox

/// Keeps other audio out of a recording: mutes the output, pauses whatever is
/// playing, or both, and puts things back afterwards.
///
/// Muting sets CoreAudio properties on the output device. There is no second
/// process to talk to, nothing to time out and no permission to hold, which is
/// why it is the option that cannot go wrong.
///
/// Pausing is harder, and an earlier version of it was removed in 0.7.3 after
/// three releases of bugs. Every one of them came from the same gap: the app
/// sent a pause without knowing whether anything was playing, so it could not
/// know whether to send a play afterwards. Guessing wrong resumed a player that
/// had been paused for hours, or, with no player at all, launched Apple Music.
/// The version here closes that gap rather than working around it — see
/// `NowPlaying` for how the question is actually answered.
///
/// Main-actor rather than an actor of its own: the CoreAudio calls are quick
/// property accesses, and running them synchronously is what lets the
/// coordinator order the mute against the microphone opening and the cues, and
/// undo it from the terminate notification, where there is no time to wait on a
/// task. The one slow thing, asking what is playing, runs in a child process
/// and is awaited.
@MainActor
final class SystemMediaController {

    // MARK: - Mute State

    /// What a mute changed, so that restoring undoes exactly that and nothing else.
    private enum Silenced {
        /// The device's own mute flag was set.
        case muteFlag(AudioObjectID)
        /// The device has no usable mute flag, so its volume was taken to zero.
        case volume(AudioObjectID, previous: Float32)
    }

    /// Set only while a mute of ours is in force. Holding the device here, rather
    /// than looking the default output up again on restore, is what keeps a
    /// mid-recording switch to headphones from unmuting the wrong device.
    private var silenced: Silenced?

    // MARK: - System Volume (CoreAudio)

    /// Silence the default output device and remember how to undo it.
    ///
    /// The mute flag is used where the device has one. Some outputs do not — an
    /// HDMI display, some USB interfaces — and for those the volume is taken to
    /// zero instead, with the previous level kept for the restore.
    func muteSystemAudio() {
        guard silenced == nil else { return }
        guard let deviceID = defaultOutputDeviceID() else {
            print("[DubScribe] SystemMediaController: Could not find default output device")
            return
        }

        // Already muted by the user. Leave it alone and record nothing, so that
        // the restore does not unmute an output they silenced on purpose.
        if isMuted(device: deviceID) == true { return }

        if setMute(device: deviceID, muted: true) {
            silenced = .muteFlag(deviceID)
            print("[DubScribe] System audio muted")
        } else if let volume = getVolume(device: deviceID), volume > 0,
                  setVolume(device: deviceID, volume: 0) {
            silenced = .volume(deviceID, previous: volume)
            print("[DubScribe] System audio silenced by volume (was \(volume))")
        } else {
            print("[DubScribe] SystemMediaController: This output can be neither muted nor turned down")
        }
    }

    /// Undo `muteSystemAudio()`. Does nothing if no mute of ours is in force, so
    /// it is safe to call on every path that ends a recording.
    func restoreSystemAudio() {
        guard let silenced else { return }
        self.silenced = nil

        switch silenced {
        case .muteFlag(let deviceID):
            setMute(device: deviceID, muted: false)
        case .volume(let deviceID, let previous):
            // Only if it is still where we left it. A level the user set during
            // the recording is theirs to keep.
            if getVolume(device: deviceID) == 0 {
                setVolume(device: deviceID, volume: previous)
            }
        }
        print("[DubScribe] System audio restored")
    }

    // MARK: - Pause Media

    /// The player a pause of ours is holding. Resume acts on this player and no
    /// other, which is what stops it from starting something that was not playing.
    private var pausedPlayer: NowPlaying?

    /// False once the recording a pause was requested for has ended. Asking what
    /// is playing takes a moment, and a very short recording can be over before
    /// the answer arrives; pausing then would stop the music after the fact.
    private var pauseStillWanted = false

    /// Runs pause and resume strictly in the order they were asked for, so a
    /// resume can never overtake the pause it belongs to.
    private var mediaTask: Task<Void, Never>?

    /// Pause whatever is playing, if anything is.
    ///
    /// Returns at once; the work happens behind it. Nothing is sent unless a
    /// player is known to be playing, so with nothing playing this does nothing
    /// at all — and leaves nothing for `resumeMedia()` to do either.
    func pauseMedia() {
        pauseStillWanted = true
        let previous = mediaTask
        mediaTask = Task { [weak self] in
            await previous?.value
            await self?.performPause()
        }
    }

    /// Resume the player `pauseMedia()` paused, if it paused one.
    func resumeMedia() {
        pauseStillWanted = false
        let previous = mediaTask
        mediaTask = Task { [weak self] in
            await previous?.value
            await self?.performResume()
        }
    }

    private func performPause() async {
        guard pausedPlayer == nil else { return }

        guard let playing = await NowPlaying.read() else {
            print("[DubScribe] Pause media: could not tell what is playing - leaving it alone")
            return
        }
        guard playing.isPlaying else {
            print("[DubScribe] Pause media: nothing is playing")
            return
        }
        guard pauseStillWanted else { return }

        sendMediaRemote(.pause)
        pausedPlayer = playing
        print("[DubScribe] Paused \(playing.bundleID)")
    }

    private func performResume() async {
        guard let paused = pausedPlayer else { return }
        pausedPlayer = nil

        // A play command goes to whichever player the system currently treats as
        // the active one. Sending it is only right while that is still the
        // player we paused. If it has quit, or another has taken its place, the
        // command would land somewhere it was never meant to — so it is not sent.
        guard let current = await NowPlaying.read(),
              current.pid == paused.pid, current.bundleID == paused.bundleID else {
            print("[DubScribe] Resume media: \(paused.bundleID) is no longer the active player - leaving it alone")
            return
        }

        sendMediaRemote(.play)
        print("[DubScribe] Resumed \(paused.bundleID)")
    }

    // MARK: - MediaRemote

    /// MediaRemote command identifiers. These are not interchangeable: 0 plays,
    /// 1 pauses, and neither is a toggle.
    private enum MediaRemoteCommand: UInt32 {
        case play = 0
        case pause = 1
    }

    /// Send a command to the system's active player, through the same private
    /// framework the keyboard's media keys go through.
    ///
    /// It cannot be aimed. The framework has variants that take a bundle
    /// identifier or a process, and from an ordinary app they are ignored: the
    /// command goes to the active player regardless (measured on macOS 27 with
    /// two players running). That is why every send here is preceded by a check
    /// of who the active player is.
    ///
    /// The framework is private, so Apple could change it. It is loaded at run
    /// time and every symbol is looked up before use, so the failure mode is
    /// that nothing is paused, not a crash.
    private func sendMediaRemote(_ command: MediaRemoteCommand) {
        guard let handle = Self.mediaRemoteHandle,
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return }
        typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
        _ = unsafeBitCast(symbol, to: SendCommand.self)(command.rawValue, nil)
    }

    private static let mediaRemoteHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    }()

    private static var hasRegisteredWithMediaRemote = false

    /// Registers as a Now Playing client, once per process.
    ///
    /// Not needed on macOS 27, where commands are delivered without it. Kept
    /// because on macOS 26 a command sent before registering was measured to be
    /// dropped, and registering ahead of time costs nothing.
    func prepareMediaControl() {
        guard !Self.hasRegisteredWithMediaRemote, let handle = Self.mediaRemoteHandle,
              let symbol = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") else { return }
        typealias Register = @convention(c) (DispatchQueue) -> Void
        unsafeBitCast(symbol, to: Register.self)(DispatchQueue.global())
        Self.hasRegisteredWithMediaRemote = true
    }

    // MARK: - CoreAudio Helpers

    private func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    private func getVolume(device: AudioObjectID) -> Float32? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    /// Returns whether the device accepted the new level.
    @discardableResult
    private func setVolume(device: AudioObjectID, volume: Float32) -> Bool {
        var vol = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol) == noErr
    }

    /// The device's mute flag, or nil if it has none that can be read.
    private func isMuted(device: AudioObjectID) -> Bool? {
        var mute: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr else { return nil }
        return mute != 0
    }

    /// Returns whether the device accepted the change. A device with no mute
    /// flag reports failure here rather than being assumed muted.
    @discardableResult
    private func setMute(device: AudioObjectID, muted: Bool) -> Bool {
        var mute: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &mute) == noErr
    }
}

/// The system's active player and whether it is playing.
///
/// This is the answer the old pause-media never had. macOS withholds playback
/// state from ordinary apps: asked directly on macOS 27, it reports "paused"
/// for a player that is audibly playing. Counting the processes that are
/// producing audio does not substitute for it either — VLC keeps its output
/// device open while paused, so it looks busy when it is silent.
///
/// The state is still given to Apple's own tools, so it is read by running one:
/// `osascript`, with a few lines of JavaScript that ask the system's Now Playing
/// service. Nothing is sent to any other app, so there is no Automation prompt.
/// It runs in its own process with a deadline, which means the worst it can do
/// is fail to answer — and no answer is treated as "do not touch anything".
private struct NowPlaying {
    let isPlaying: Bool
    let pid: Int32
    let bundleID: String

    /// How long the helper may take before it is given up on. It normally
    /// answers in about a tenth of a second.
    private static let deadline: TimeInterval = 2

    private static let script = """
        function run() {
            try {
                ObjC.import('Foundation');
                $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework').load;
                const Request = $.NSClassFromString('MRNowPlayingRequest');
                const path = Request.localNowPlayingPlayerPath;
                if (path.isNil() || path.client.isNil()) return 'none';
                const client = path.client;
                const bundle = client.bundleIdentifier.isNil() ? '' : client.bundleIdentifier.js;
                return [Request.localIsPlaying ? 'playing' : 'paused', client.processIdentifier, bundle].join('|');
            } catch (error) {
                return 'unavailable';
            }
        }
        """

    /// The active player, or nil if there is none or it could not be determined.
    static func read() async -> NowPlaying? {
        guard let output = await runHelper() else { return nil }
        let fields = output.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[0] == "playing" || fields[0] == "paused",
              let pid = Int32(fields[1]), pid > 0 else { return nil }
        return NowPlaying(isPlaying: fields[0] == "playing", pid: pid, bundleID: String(fields[2]))
    }

    private static func runHelper() async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            // Called exactly once, whether the helper finishes or is terminated
            // at the deadline. Its output is a single short line, so reading it
            // here cannot block on a full pipe.
            process.terminationHandler = { _ in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
