import Foundation

struct AppSettings: Codable {
    // Hotkeys
    var holdHotkey: Hotkey          // press-and-hold to record
    var pushHotkey: Hotkey          // toggle: press once to start, again to stop

    // Audio
    var selectedInputDeviceID: String?
    var playSounds: Bool

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
        voiceActivationEnabled: false,
        voiceActivationThreshold: 0.02,
        voiceActivationStopDelay: 1.0,
        launchAtLogin: false,
        hotkey: nil
    )

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
