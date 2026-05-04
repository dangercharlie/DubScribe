import Foundation
import AVFoundation
import AppKit

/// Handles microphone permission requests and status checks.
enum PermissionHelpers {

    static var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var isMicrophoneAuthorized: Bool {
        microphoneAuthorizationStatus == .authorized
    }

    /// Request microphone permission. Completion is called on the main thread.
    static func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static var microphoneStatusMessage: String {
        switch microphoneAuthorizationStatus {
        case .authorized:
            return "Microphone access granted."
        case .denied:
            return "Microphone access denied. Go to System Settings → Privacy & Security → Microphone to enable it."
        case .restricted:
            return "Microphone access is restricted by a system policy."
        case .notDetermined:
            return "Microphone permission not yet requested."
        @unknown default:
            return "Unknown microphone permission status."
        }
    }

    /// Opens the Privacy & Security > Microphone section in System Settings.
    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the Privacy & Security > Accessibility section in System Settings.
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
