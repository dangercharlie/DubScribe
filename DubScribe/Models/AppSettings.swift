import Foundation

struct AppSettings: Codable {
    // Hotkeys
    var holdHotkey: Hotkey          // press-and-hold to record
    var pushHotkey: Hotkey          // toggle: press once to start, again to stop

    // Audio
    var selectedInputDeviceID: String?
    var playSounds: Bool
    var muteSystemAudioDuringRecording: Bool      // mute output when recording
    var pauseMediaDuringRecording: Bool            // pause playing media when recording
    var mediaResumeDelay: Double                   // seconds (0.0–1.0) before resuming media

    // Voice activation
    var voiceActivationEnabled: Bool
    var voiceActivationThreshold: Float   // 0.0 (quiet) … 1.0 (loud), default ~0.02
    var voiceActivationStopDelay: Double  // seconds, default 1.0

    // General
    var launchAtLogin: Bool

    // Legacy key kept so old saved data still decodes
    var hotkey: Hotkey?

    static let `default` = AppSettings(
        holdHotkey: .defaultHoldHotkey,
        pushHotkey: .defaultPushHotkey,
        selectedInputDeviceID: nil,
        playSounds: true,
        muteSystemAudioDuringRecording: false,
        pauseMediaDuringRecording: false,
        mediaResumeDelay: 0.0,
        voiceActivationEnabled: false,
        voiceActivationThreshold: 0.02,
        voiceActivationStopDelay: 1.0,
        launchAtLogin: false,
        hotkey: nil
    )

    // Explicit memberwise init (required because custom init(from:) removes synthesised one)
    init(
        holdHotkey: Hotkey,
        pushHotkey: Hotkey,
        selectedInputDeviceID: String?,
        playSounds: Bool,
        muteSystemAudioDuringRecording: Bool,
        pauseMediaDuringRecording: Bool,
        mediaResumeDelay: Double,
        voiceActivationEnabled: Bool,
        voiceActivationThreshold: Float,
        voiceActivationStopDelay: Double,
        launchAtLogin: Bool,
        hotkey: Hotkey?
    ) {
        self.holdHotkey = holdHotkey
        self.pushHotkey = pushHotkey
        self.selectedInputDeviceID = selectedInputDeviceID
        self.playSounds = playSounds
        self.muteSystemAudioDuringRecording = muteSystemAudioDuringRecording
        self.pauseMediaDuringRecording = pauseMediaDuringRecording
        self.mediaResumeDelay = mediaResumeDelay
        self.voiceActivationEnabled = voiceActivationEnabled
        self.voiceActivationThreshold = voiceActivationThreshold
        self.voiceActivationStopDelay = voiceActivationStopDelay
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
    }

    // Custom decoder: ensures existing V2 saves (missing new keys) decode with defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holdHotkey                      = try c.decode(Hotkey.self, forKey: .holdHotkey)
        pushHotkey                      = try c.decode(Hotkey.self, forKey: .pushHotkey)
        selectedInputDeviceID           = try c.decodeIfPresent(String.self, forKey: .selectedInputDeviceID)
        playSounds                      = try c.decode(Bool.self, forKey: .playSounds)
        muteSystemAudioDuringRecording  = try c.decodeIfPresent(Bool.self, forKey: .muteSystemAudioDuringRecording) ?? false
        pauseMediaDuringRecording       = try c.decodeIfPresent(Bool.self, forKey: .pauseMediaDuringRecording) ?? false
        mediaResumeDelay                = try c.decodeIfPresent(Double.self, forKey: .mediaResumeDelay) ?? 0.0
        voiceActivationEnabled          = try c.decode(Bool.self, forKey: .voiceActivationEnabled)
        voiceActivationThreshold        = try c.decode(Float.self, forKey: .voiceActivationThreshold)
        voiceActivationStopDelay        = try c.decode(Double.self, forKey: .voiceActivationStopDelay)
        launchAtLogin                   = try c.decode(Bool.self, forKey: .launchAtLogin)
        hotkey                          = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
    }

    private static let userDefaultsKey = "AppSettingsV2"

    static func load() -> AppSettings {
        // Try new V2 key first
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        // Migrate from V1 key if present
        if let data = UserDefaults.standard.data(forKey: "AppSettings"),
           let old = try? JSONDecoder().decode(AppSettings.self, from: data) {
            var migrated = AppSettings.default
            migrated.holdHotkey = old.hotkey ?? .defaultHoldHotkey
            migrated.playSounds = old.playSounds
            migrated.launchAtLogin = old.launchAtLogin
            migrated.selectedInputDeviceID = old.selectedInputDeviceID
            return migrated
        }
        return .default
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }
}
