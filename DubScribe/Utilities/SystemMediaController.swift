import Foundation
import CoreAudio
import AudioToolbox
import AppKit
import CoreGraphics

/// Controls system audio volume and media playback state.
/// Used to mute/unmute and pause/resume media during recordings.
actor SystemMediaController {

    // MARK: - Volume State

    /// The volume level captured before muting, so we can restore it.
    private var savedVolume: Float?
    /// Whether we actively muted the system (to avoid restoring when we didn't mute).
    private var didMute = false

    // MARK: - Media State

    /// Which apps we paused, so resume targets only sources DubScribe touched.
    private enum PausedSource: Hashable {
        case spotify
        case music
        case vlc
        case chrome
        case mediaRemote
    }
    private var pausedSources = Set<PausedSource>()

    // MARK: - Third-Party Audio Detection

    /// Whether any process *other than DubScribe* is currently producing audio output.
    ///
    /// This exists to answer one narrow question: is there anything at all for the
    /// MediaRemote fallback to pause? Its absence caused a user-visible bug. The
    /// fallback used to fire unconditionally — `sendMediaRemote` reports whether the
    /// symbol resolved, not whether anything paused — so `resumeMedia()` later sent
    /// `play` with nothing playing. MediaRemote reads a bare play as "start
    /// playback" and **launches Apple Music**. Reproduced 6 times out of 6.
    ///
    /// Note this deliberately ignores our own process. The start cue is audio output,
    /// so including ourselves would make the answer permanently `true` and the gate
    /// useless.
    ///
    /// Public CoreAudio only — no private framework, no permission. Returns `false`
    /// on macOS below 14.2, where the per-process API does not exist. That is the
    /// safe default: we skip a pause we cannot verify rather than risk launching
    /// Music. The explicit players above are unaffected, because they are only
    /// reached when their app is already running.
    private func isOtherProcessProducingAudio() -> Bool {
        guard #available(macOS 14.2, *) else { return false }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return false }

        var processObjects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processObjects
        ) == noErr else { return false }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        for object in processObjects {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &isRunning) == noErr,
                  isRunning != 0 else { continue }

            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }

            if pid != ownPID { return true }
        }

        return false
    }

    // MARK: - System Volume (CoreAudio)

    /// Mute the default output device by setting volume to 0 and enabling mute.
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

    // MARK: - Media Playback

    /// Pause any currently playing media.
    func pauseMedia() {
        pausedSources.removeAll()

        // Try Spotify first
        if isAppRunning("com.spotify.client") {
            let state = spotifyPlayerState()
            logMedia("Spotify player state: \(state ?? "nil")")
            if state == "playing" {
                runAppleScript("""
                    tell application "Spotify"
                        pause
                    end tell
                    """)
                pausedSources.insert(.spotify)
                logMedia("Paused Spotify")
            }
        }

        // Try Apple Music
        if isAppRunning("com.apple.Music") {
            let state = musicPlayerState()
            logMedia("Music player state: \(state ?? "nil")")
            if state == "playing" {
                runAppleScript("""
                    tell application "Music"
                        pause
                    end tell
                    """)
                pausedSources.insert(.music)
                logMedia("Paused Music")
            }
        }

        // Try VLC. VLC exposes a read-only "playing" state and a toggle "play" command.
        if isAppRunning("org.videolan.vlc") {
            let isPlaying = vlcIsPlaying()
            logMedia("VLC playing state: \(isPlaying.map(String.init) ?? "nil")")
            if isPlaying == true {
                runAppleScript("""
                    tell application "VLC"
                        play
                    end tell
                    """)
                pausedSources.insert(.vlc)
                logMedia("Paused VLC")
            } else {
                logMedia("VLC current item while not playing: \(vlcCurrentItemSummary() ?? "nil")")
            }
        }

        // Try Chrome tabs directly. This catches YouTube even when macOS blocks media-key events.
        if pauseChromeMedia() {
            pausedSources.insert(.chrome)
            logMedia("Paused Chrome media")
        }

        // Fallback for anything the explicit players above did not catch (Safari,
        // a podcast app, an audio player with no scripting dictionary). This used
        // to post a synthetic media key with CGEvent, which requires the user to
        // grant Accessibility for a feature described in Settings as simply
        // "Pause media playback" — and failed silently without it.
        //
        // MediaRemote does the same job through the same channel the keyboard's
        // media keys use, and needs no permission at all.
        //
        // Gated on there actually being audio to pause. Without this check the
        // bare `play` in resumeMedia() launches Apple Music when nothing was
        // playing — see isOtherProcessProducingAudio().
        if pausedSources.isEmpty {
            if isOtherProcessProducingAudio() {
                sendMediaRemote(.pause)
                pausedSources.insert(.mediaRemote)
                logMedia("Paused via MediaRemote")
            } else {
                // Nothing was playing, so nothing is paused. Leaving this empty is
                // what stops resumeMedia() from sending a stray play command.
                logMedia("No media detected as playing - skipping pause")
            }
        }
    }

    /// Resume media playback if we previously paused it.
    func resumeMedia() {
        guard !pausedSources.isEmpty else { return }

        if pausedSources.contains(.spotify) {
            runAppleScript("""
                tell application "Spotify"
                    play
                end tell
                """)
            logMedia("Resumed Spotify")
        }

        if pausedSources.contains(.music) {
            runAppleScript("""
                tell application "Music"
                    play
                end tell
                """)
            logMedia("Resumed Music")
        }

        if pausedSources.contains(.vlc) {
            runAppleScript("""
                tell application "VLC"
                    play
                end tell
                """)
            logMedia("Resumed VLC")
        }

        if pausedSources.contains(.chrome) {
            resumeChromeMedia()
        }

        if pausedSources.contains(.mediaRemote) {
            // Explicitly Play, not another Pause: they are different commands.
            sendMediaRemote(.play)
            logMedia("Resumed via MediaRemote")
        }

        pausedSources.removeAll()
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

    // MARK: - AppleScript Helpers

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            logMedia("AppleScript error: \(error)")
            return nil
        }
        return result?.stringValue
    }

    private func isAppRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.isTerminated == false
    }

    /// Query Spotify player state using block form (one-liner `tell...to get player state` fails).
    private func spotifyPlayerState() -> String? {
        runAppleScript("""
            tell application "Spotify"
                return player state as text
            end tell
            """)
    }

    /// Query Music player state.
    private func musicPlayerState() -> String? {
        runAppleScript("""
            tell application "Music"
                return player state as text
            end tell
            """)
    }

    /// Query VLC's playback state without toggling playback.
    private func vlcIsPlaying() -> Bool? {
        guard let result = runAppleScript("""
            tell application "VLC"
                return playing
            end tell
            """)?.lowercased() else {
            return nil
        }
        return result == "true" ? true : result == "false" ? false : nil
    }

    private func vlcCurrentItemSummary() -> String? {
        runAppleScript("""
            tell application "VLC"
                try
                    return ((current time as text) & "|" & (name of current item as text))
                on error
                    return "none"
                end try
            end tell
            """)
    }

    /// Pause media elements in Chrome tabs without relying on global media-key permissions.
    private func pauseChromeMedia() -> Bool {
        guard isAppRunning("com.google.Chrome") else { return false }

        let scriptResult = runAppleScript("""
            tell application "Google Chrome"
                if (count of windows) is 0 then return "no-windows"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            set tabURL to URL of browserTab
                            if tabURL starts with "http" then
                                set pauseResult to execute browserTab javascript "\(appleScriptStringLiteral(Self.chromePauseJavaScript))"
                                set pauseResultText to pauseResult as text
                                if pauseResultText starts with "paused:" then return pauseResultText
                            end if
                        on error
                        end try
                    end repeat
                end repeat
                return "none"
            end tell
            """)

        logMedia("Chrome media pause result: \(scriptResult ?? "nil")")
        return scriptResult?.hasPrefix("paused:") == true
    }

    /// Resume only the Chrome media elements DubScribe paused.
    private func resumeChromeMedia() {
        guard isAppRunning("com.google.Chrome") else {
            logMedia("Chrome is not running - skipping media resume")
            return
        }

        let scriptResult = runAppleScript("""
            tell application "Google Chrome"
                if (count of windows) is 0 then return "no-windows"
                set resumedCount to 0
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        try
                            set tabURL to URL of browserTab
                            if tabURL starts with "http" then
                                set resumeResult to execute browserTab javascript "\(appleScriptStringLiteral(Self.chromeResumeJavaScript))"
                                set resumedCount to resumedCount + (resumeResult as integer)
                            end if
                        on error
                        end try
                    end repeat
                end repeat
                return "resumed:" & resumedCount
            end tell
            """)

        logMedia("Chrome media resume result: \(scriptResult ?? "nil")")
    }

    private static let chromePauseJavaScript = """
        (function(){var media=Array.prototype.slice.call(document.querySelectorAll('video,audio'));var paused=0;media.forEach(function(m){try{if(!m.paused&&!m.ended){m.dataset.dubscribePaused='1';m.pause();paused++;}}catch(e){}});return paused>0?'paused:'+paused:'none';})()
        """

    private static let chromeResumeJavaScript = """
        (function(){var media=Array.prototype.slice.call(document.querySelectorAll('video,audio'));var resumed=0;media.forEach(function(m){try{if(m.dataset.dubscribePaused==='1'){delete m.dataset.dubscribePaused;m.play();resumed++;}}catch(e){}});return ''+resumed;})()
        """

    private func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "")
    }

    /// Check if there is an active Now Playing session via a lightweight shell check.

    // MARK: - MediaRemote

    /// Pauses whatever is playing, through the same private framework the
    /// keyboard media keys go through.
    ///
    /// Why this and not CGEvent: posting a synthetic media key needs the
    /// Accessibility permission, which is a large ask for "pause my music while
    /// I record" and is invisible when it is missing — the toggle just does
    /// nothing. MediaRemote is what every Open Now Playing client on macOS uses,
    /// and needs no permission.
    ///
    /// It is a private framework, which is a real trade-off: Apple could change
    /// it. Two things make it acceptable here. It is loaded dynamically, so it
    /// cannot fail at launch or link time — only when the function is called,
    /// and then it degrades to "did not pause" rather than crashing. And the
    /// media-key route is gone rather than kept as a fallback, so there is no
    /// path that quietly works better if the user has granted Accessibility.
    ///
    /// The registration call is not optional: MediaRemote ignores commands from
    /// a process that has not registered as a Now Playing client. Measured — the
    /// same `MRMediaRemoteSendCommand(1)` that pauses a track does nothing at all
    /// when sent first, without it.
    /// MediaRemote command identifiers, verified on macOS 26 by driving a playing
    /// track and observing the result of each:
    ///
    ///   1 -> paused, 0 -> played, 2 -> toggled
    ///
    /// These are NOT interchangeable. An earlier version of this used 1 for both
    /// pause and resume, on the assumption that 1 was a toggle; playback then
    /// paused correctly and never resumed, which read as a flaky feature rather
    /// than a wrong constant.
    private enum MediaRemoteCommand: Int32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
    }

    /// Send a command to MediaRemote.
    ///
    /// Deliberately returns nothing. It used to return `Bool`, which was read as
    /// "something paused" when all it could ever mean was "the symbol resolved".
    /// Callers gated on that value concluded a pause had happened when it had not,
    /// and the later `play` launched Apple Music. There is no way to know locally
    /// whether a command took effect, so this no longer claims to.
    ///
    /// Use `isOtherProcessProducingAudio()` to decide whether to send at all.
    private func sendMediaRemote(_ command: MediaRemoteCommand) {
        guard let handle = Self.mediaRemoteHandle else { return }

        // Registration happens at launch (see prepareMediaControl); this is the
        // belt-and-braces path for the unlikely case that pause is reached first.
        Self.registerWithMediaRemoteIfNeeded()

        typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Void
        guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else { return }
        unsafeBitCast(sym, to: SendCommand.self)(command.rawValue, nil)
    }

    /// The loaded MediaRemote framework, or nil if it cannot be opened.
    ///
    /// Resolved once and cached: `dlopen` on every recording would be wasteful,
    /// and a failure here is not recoverable.
    private static let mediaRemoteHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)
    }()

    /// Whether this process has registered as a Now Playing client yet.
    ///
    /// Static because registration is process-wide, not per-instance, and the
    /// guard has to be shared: two instances registering twice would be wrong,
    /// and the flag is what makes `prepareMediaControl` idempotent.
    private nonisolated(unsafe) static var hasRegisteredWithMediaRemote = false

    /// Registers as a Now Playing client, once per process.
    ///
    /// This must happen well before the first pause, not lazily at the moment of
    /// it. Measured on macOS 26: firing registration and the pause command in the
    /// same run paused only 3 times out of 6, while a process that registered once
    /// at startup and then paused later succeeded 9 times out of 9. The
    /// registration is asynchronous inside MediaRemote, so a command sent
    /// immediately after it is simply dropped.
    ///
    /// Called from `AppCoordinator` at launch, which costs nothing (the framework
    /// is loaded, a notification registration is made) and removes the race
    /// entirely.
    nonisolated func prepareMediaControl() {
        Self.registerWithMediaRemoteIfNeeded()
    }

    private static func registerWithMediaRemoteIfNeeded() {
        guard !hasRegisteredWithMediaRemote, let handle = Self.mediaRemoteHandle else { return }
        typealias Register = @convention(c) (DispatchQueue) -> Void
        guard let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") else { return }
        unsafeBitCast(sym, to: Register.self)(DispatchQueue.global())
        hasRegisteredWithMediaRemote = true
    }

    /// Diagnostics go to the console only.
    ///
    /// This previously also appended to ~/Library/Logs/DubScribe-media.log on
    /// every media event, with no rotation and no size cap — a file that grows
    /// for the life of the install, in a location the app never mentions, for an
    /// app whose whole pitch is that it stays out of the way. `print` is enough
    /// to debug the media path when it is being worked on, and the Console is
    /// where anyone debugging would look anyway.
    private func logMedia(_ message: String) {
        print("[DubScribe] \(message)")
    }
}
