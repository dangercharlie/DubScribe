import Foundation

struct AppSettings: Codable {
    var hotkey: Hotkey
    var launchAtLogin: Bool
    var playSounds: Bool
    var selectedInputDeviceID: String?

    static let `default` = AppSettings(
        hotkey: .defaultHotkey,
        launchAtLogin: false,
        playSounds: true,
        selectedInputDeviceID: nil
    )

    private static let userDefaultsKey = "AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }
}
