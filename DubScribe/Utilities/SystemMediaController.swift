import Foundation
import CoreAudio
import AudioToolbox

/// Mutes the system output for the duration of a recording, and restores it after.
///
/// This is deliberately the *only* thing the app does to other audio. Until
/// 0.7.3 it also paused other media players, by driving Apple Events at each
/// player (`tell application "Music" to pause`) with a MediaRemote fallback for
/// anything unrecognised. That was removed: it needed permission for each player,
/// it could hang on a target that never answered, and the resume half could start
/// playback in an app that had not been playing — which is how finishing a
/// recording ended up opening Apple Music.
///
/// Muting is a different kind of operation. It sets CoreAudio properties on the
/// output device, so there is no second process to talk to, nothing to time out,
/// no permission to hold, and no way for it to launch anything.
///
/// Main-actor rather than an actor of its own: the CoreAudio calls are quick
/// property accesses, and running them synchronously is what lets the
/// coordinator order the mute against the microphone opening and the cues, and
/// undo it from the terminate notification, where there is no time to wait on a
/// task.
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
