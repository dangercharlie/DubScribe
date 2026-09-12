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
/// no permission to hold, and no way for it to launch anything. The recording is
/// kept clean for the same reason the pause approach was reaching for, without
/// the ways it could go wrong.
actor SystemMediaController {

    // MARK: - Volume State

    /// The volume level captured before muting, so we can restore it.
    private var savedVolume: Float?
    /// Whether we actively muted the system (to avoid restoring when we didn't mute).
    private var didMute = false

    // MARK: - System Volume (CoreAudio)

    /// Mute the default output device and remember the level to restore.
    ///
    /// The volume is saved even though muting uses the device's own mute flag:
    /// some output devices ignore that flag, and for those the saved level is
    /// what lets `restoreSystemAudio()` put things back.
    func muteSystemAudio() {
        guard let deviceID = defaultOutputDeviceID() else {
            print("[DubScribe] SystemMediaController: Could not find default output device")
            return
        }

        // Save current volume before muting
        savedVolume = getVolume(device: deviceID)
        setMute(device: deviceID, muted: true)
        didMute = true
        print("[DubScribe] System audio muted (saved volume: \(savedVolume ?? -1))")
    }

    /// Restore the system audio to its pre-mute state.
    func restoreSystemAudio() {
        // `didMute` matters: without it, stopping a recording when mute was never
        // switched on would still unmute the user's deliberately muted output.
        guard didMute, let deviceID = defaultOutputDeviceID() else { return }

        setMute(device: deviceID, muted: false)

        // Restore saved volume if we captured one
        if let vol = savedVolume {
            setVolume(device: deviceID, volume: vol)
        }

        didMute = false
        savedVolume = nil
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

    private func getVolume(device: AudioObjectID) -> Float {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return volume
    }

    private func setVolume(device: AudioObjectID, volume: Float) {
        var vol = volume
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol)
    }

    private func setMute(device: AudioObjectID, muted: Bool) {
        var mute: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(device, &address, 0, nil, size, &mute)
    }
}
