import Foundation

struct AppSettings: Codable {
    // Hotkeys
    var holdHotkey: Hotkey          // press-and-hold to record
    var pushHotkey: Hotkey          // toggle: press once to start, again to stop

    // Audio
    var selectedInputDeviceID: String?
    var playSounds: Bool
    /// Opt-in start cue. Off by default.
    ///
    /// The on-screen indicator answers "did it start?" without putting a sound
    /// into the room, and while this is off there is no pre-roll delay before
    /// capture begins, so recordings start instantly.
    var playStartCue: Bool
    var muteSystemAudioDuringRecording: Bool      // mute output when recording
    var pauseMediaDuringRecording: Bool            // pause playing media when recording
    var mediaResumeDelay: Double                   // seconds (0.0–1.0) before resuming media

    /// Threshold for the microphone-test meter only.
    /// (Supersedes the old voice-activation threshold, removed in 0.7.0.)
    var micTestThreshold: Float

    // Housekeeping
    /// When true, clips move to the Trash once they are no longer pasteable.
    var autoDeleteClips: Bool
    /// How long a displaced clip lingers before being trashed, in minutes.
    var clipRetentionMinutes: Double
    /// Backstop cap on total clips-folder size, in megabytes.
    var maxClipsSizeMB: Double

    // Visual feedback
    /// Floating on-screen waveform shown while recording.
    var showRecordingHUD: Bool
    /// How opaque the indicator's backdrop is, 0…1.
    ///
    /// Deliberately a tunable rather than a fixed value: how transparent the
    /// panel should look depends on your desktop and your eyes, and the right
    /// number is easier to dial in than to guess.
    var hudOpacity: Double

    // General
    var launchAtLogin: Bool

    // Legacy key kept so old saved data still decodes
    var hotkey: Hotkey?

    // Explicit CodingKeys.
    //
    // These are required rather than synthesised because 0.7.0 removed the
    // voice-activation fields. Without listing them here the synthesised enum
    // would drop those cases entirely and the legacy blob would no longer be
    // readable at all. Listing a key that has no matching property is legal:
    // Swift simply never encodes it.
    private enum CodingKeys: String, CodingKey {
        case holdHotkey
        case pushHotkey
        case selectedInputDeviceID
        case playSounds
        case playStartCue
        case showRecordingHUD
        case hudOpacity
        case muteSystemAudioDuringRecording
        case pauseMediaDuringRecording
        case mediaResumeDelay
        case micTestThreshold
        case autoDeleteClips
        case clipRetentionMinutes
        case maxClipsSizeMB
        case launchAtLogin
        case hotkey
        // Legacy — read-only, never written.
        case voiceActivationEnabled
        case voiceActivationThreshold
        case voiceActivationStopDelay
    }

    static let `default` = AppSettings(
        holdHotkey: .defaultHoldHotkey,
        pushHotkey: .defaultPushHotkey,
        selectedInputDeviceID: nil,
        playSounds: true,
        playStartCue: false,
        muteSystemAudioDuringRecording: false,
        pauseMediaDuringRecording: false,
        mediaResumeDelay: 0.0,
        micTestThreshold: 0.02,
        autoDeleteClips: true,
        clipRetentionMinutes: 2.0,
        maxClipsSizeMB: 250.0,
        showRecordingHUD: true,
        hudOpacity: 1.0,
        launchAtLogin: false,
        hotkey: nil
    )

    // Explicit memberwise init (required because custom init(from:) removes the synthesised one)
    init(
        holdHotkey: Hotkey,
        pushHotkey: Hotkey,
        selectedInputDeviceID: String?,
        playSounds: Bool,
        playStartCue: Bool,
        muteSystemAudioDuringRecording: Bool,
        pauseMediaDuringRecording: Bool,
        mediaResumeDelay: Double,
        micTestThreshold: Float,
        autoDeleteClips: Bool,
        clipRetentionMinutes: Double,
        maxClipsSizeMB: Double,
        showRecordingHUD: Bool,
        hudOpacity: Double,
        launchAtLogin: Bool,
        hotkey: Hotkey?
    ) {
        self.holdHotkey = holdHotkey
        self.pushHotkey = pushHotkey
        self.selectedInputDeviceID = selectedInputDeviceID
        self.playSounds = playSounds
        self.playStartCue = playStartCue
        self.muteSystemAudioDuringRecording = muteSystemAudioDuringRecording
        self.pauseMediaDuringRecording = pauseMediaDuringRecording
        self.mediaResumeDelay = mediaResumeDelay
        self.micTestThreshold = micTestThreshold
        self.autoDeleteClips = autoDeleteClips
        self.clipRetentionMinutes = clipRetentionMinutes
        self.maxClipsSizeMB = maxClipsSizeMB
        self.showRecordingHUD = showRecordingHUD
        self.hudOpacity = hudOpacity
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
    }

    // Custom decoder.
    //
    // IMPORTANT: every field uses decodeIfPresent with a fallback. This is
    // deliberate and load-bearing.
    //
    // 0.7.0 removed the voice-activation keys. With the previous
    // non-optional `try c.decode(...)` calls, removing them made decoding
    // throw `keyNotFound`; `load()`'s `try?` swallowed that and returned
    // `.default`, so every user silently lost their hotkeys, input device and
    // preferences — the app appeared to reset itself. This was verified
    // empirically before the change was made.
    //
    // Rule for future changes: NEVER add a non-optional `decode` for a new
    // key. A missing key must always fall back to a default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings.default

        holdHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .holdHotkey) ?? fallback.holdHotkey
        pushHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .pushHotkey) ?? fallback.pushHotkey
        selectedInputDeviceID = try c.decodeIfPresent(String.self, forKey: .selectedInputDeviceID)
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? fallback.playSounds
        playStartCue = try c.decodeIfPresent(Bool.self, forKey: .playStartCue) ?? fallback.playStartCue
        showRecordingHUD = try c.decodeIfPresent(Bool.self, forKey: .showRecordingHUD) ?? fallback.showRecordingHUD
        hudOpacity = try c.decodeIfPresent(Double.self, forKey: .hudOpacity) ?? fallback.hudOpacity
        muteSystemAudioDuringRecording = try c.decodeIfPresent(Bool.self, forKey: .muteSystemAudioDuringRecording) ?? fallback.muteSystemAudioDuringRecording
        pauseMediaDuringRecording = try c.decodeIfPresent(Bool.self, forKey: .pauseMediaDuringRecording) ?? fallback.pauseMediaDuringRecording
        mediaResumeDelay = try c.decodeIfPresent(Double.self, forKey: .mediaResumeDelay) ?? fallback.mediaResumeDelay

        // A user who tuned the old voice-activation slider keeps their tuning
        // rather than snapping back to the default.
        if let legacy = try c.decodeIfPresent(Float.self, forKey: .voiceActivationThreshold) {
            micTestThreshold = legacy
        } else {
            micTestThreshold = try c.decodeIfPresent(Float.self, forKey: .micTestThreshold) ?? fallback.micTestThreshold
        }

        autoDeleteClips = try c.decodeIfPresent(Bool.self, forKey: .autoDeleteClips) ?? fallback.autoDeleteClips
        clipRetentionMinutes = try c.decodeIfPresent(Double.self, forKey: .clipRetentionMinutes) ?? fallback.clipRetentionMinutes
        maxClipsSizeMB = try c.decodeIfPresent(Double.self, forKey: .maxClipsSizeMB) ?? fallback.maxClipsSizeMB
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)

        // Legacy voice-activation keys are intentionally not read into any
        // property. They remain in `CodingKeys` only so old blobs stay
        // decodable; they are dropped on the next save.
    }

    /// Explicit encoding.
    ///
    /// Required because `CodingKeys` deliberately carries the legacy
    /// voice-activation cases, which have no backing property — that breaks
    /// synthesis of `Encodable`. Writing the encoder by hand also guarantees
    /// the dead keys are never written again.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(holdHotkey, forKey: .holdHotkey)
        try c.encode(pushHotkey, forKey: .pushHotkey)
        try c.encodeIfPresent(selectedInputDeviceID, forKey: .selectedInputDeviceID)
        try c.encode(playSounds, forKey: .playSounds)
        try c.encode(playStartCue, forKey: .playStartCue)
        try c.encode(showRecordingHUD, forKey: .showRecordingHUD)
        try c.encode(hudOpacity, forKey: .hudOpacity)
        try c.encode(muteSystemAudioDuringRecording, forKey: .muteSystemAudioDuringRecording)
        try c.encode(pauseMediaDuringRecording, forKey: .pauseMediaDuringRecording)
        try c.encode(mediaResumeDelay, forKey: .mediaResumeDelay)
        try c.encode(micTestThreshold, forKey: .micTestThreshold)
        try c.encode(autoDeleteClips, forKey: .autoDeleteClips)
        try c.encode(clipRetentionMinutes, forKey: .clipRetentionMinutes)
        try c.encode(maxClipsSizeMB, forKey: .maxClipsSizeMB)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encodeIfPresent(hotkey, forKey: .hotkey)
        // voiceActivationEnabled / Threshold / StopDelay are intentionally not
        // encoded. See the note in init(from:).
    }

    private static let userDefaultsKey = "AppSettingsV2"

    /// Result of a load, so callers can distinguish "fresh install" from
    /// "stored data we could not read".
    enum LoadResult {
        case loaded(AppSettings)
        case freshInstall
        case recoveredFromCorrupt
    }

    static func loadResult() -> LoadResult {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            if let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return .loaded(settings)
            }
            // Data exists but is unreadable. Do not masquerade as a fresh
            // install — the caller can surface this instead.
            return .recoveredFromCorrupt
        }

        // Migrate from V1 key if present
        if let data = UserDefaults.standard.data(forKey: "AppSettings"),
           let old = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var migrated = AppSettings.default
            migrated.holdHotkey = old.hotkey ?? .defaultHoldHotkey
            migrated.playSounds = old.playSounds
            migrated.launchAtLogin = old.launchAtLogin
            migrated.selectedInputDeviceID = old.selectedInputDeviceID
            return .loaded(migrated)
        }

        return .freshInstall
    }

    static func load() -> AppSettings {
        switch loadResult() {
        case .loaded(let settings): return settings
        case .freshInstall, .recoveredFromCorrupt: return .default
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }
}
