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
        case mediaKey
    }
    private var pausedSources = Set<PausedSource>()

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

        // Fallback: check if any system media is playing via Now Playing
        // and simulate a media pause key
        if pausedSources.isEmpty, isNowPlayingActive() {
            if simulateMediaKey(keyType: 16) {
                pausedSources.insert(.mediaKey)
                logMedia("Sent media pause key event")
            } else {
                logMedia("Could not send media pause key event")
            }
        } else if pausedSources.isEmpty {
            logMedia("No media detected as playing - skipping pause")
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

        if pausedSources.contains(.mediaKey) {
            if simulateMediaKey(keyType: 16) {
                logMedia("Sent media play key event")
            } else {
                logMedia("Could not send media play key event")
            }
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
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol)
    }

    private func setMute(device: AudioObjectID, muted: Bool) {
        var mute: UInt32 = muted ? 1 : 0
        var size = UInt32(MemoryLayout<UInt32>.size)
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
    private func isNowPlayingActive() -> Bool {
        // Use Media Remote private framework via nowplaying-cli if available,
        // otherwise assume something might be playing so the key press can toggle.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["bash", "-c",
            "command -v nowplaying-cli >/dev/null 2>&1 && nowplaying-cli get playbackRate 2>/dev/null || echo unknown"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logMedia("Now Playing playbackRate probe: \(output.isEmpty ? "empty" : output)")
            // If we get a playback rate > 0, media is playing
            if let rate = Double(output), rate > 0 { return true }
            // If "unknown" (no nowplaying-cli), be optimistic and try the key
            if output == "unknown" { return true }
        } catch {
            // Can't check — be optimistic
            logMedia("Now Playing playbackRate probe failed: \(error.localizedDescription)")
            return true
        }
        return false
    }

    // MARK: - Media Key Simulation

    /// Simulate a media key press using CGEvent.
    /// Key types: 16 = Play/Pause, 7 = Previous, 6 = Next
    @discardableResult
    private func simulateMediaKey(keyType: Int) -> Bool {
        let preflightGranted = CGPreflightPostEventAccess()
        logMedia("Media key post access preflight: \(preflightGranted)")
        let isAuthorized = preflightGranted || CGRequestPostEventAccess()
        guard isAuthorized else {
            logMedia("Media key event access is not granted. Enable DubScribe in Privacy & Security > Accessibility.")
            return false
        }

        func postMediaKeyEvent(down: Bool) -> Bool {
            let flags = down ? 0xa00 : 0xb00
            let data1 = (keyType << 16) | flags
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            guard let cgEvent = event?.cgEvent else { return false }
            cgEvent.post(tap: .cghidEventTap)
            return true
        }

        let postedDown = postMediaKeyEvent(down: true)
        let postedUp = postMediaKeyEvent(down: false)
        let didPost = postedDown && postedUp
        logMedia("Media key post result for keyType \(keyType): \(didPost)")
        return didPost
    }

    private func logMedia(_ message: String) {
        let line = "[DubScribe] \(message)"
        print(line)

        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let logsURL = libraryURL.appendingPathComponent("Logs", isDirectory: true)
        let logURL = logsURL.appendingPathComponent("DubScribe-media.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(timestamp) \(line)\n".data(using: .utf8) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL)
            }
        } catch {
            print("[DubScribe] Could not write media log: \(error.localizedDescription)")
        }
    }
}
