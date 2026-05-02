import Foundation
import ServiceManagement

/// Manages the launch-at-login registration using SMAppService (macOS 13+).
@MainActor
final class LoginItemManager: ObservableObject {

    @Published var isEnabled: Bool = false

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            isEnabled = enabled
        } catch {
            // Silently reflect the actual state on failure
            isEnabled = service.status == .enabled
            print("LoginItemManager error: \(error)")
        }
    }
}
