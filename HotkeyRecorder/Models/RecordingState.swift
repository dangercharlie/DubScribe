import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date)
    case processing
    case copied(URL)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording…"
        case .processing:
            return "Processing…"
        case .copied:
            return "Copied to clipboard"
        case .failed(let msg):
            return "Error: \(msg)"
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var copiedURL: URL? {
        if case .copied(let url) = self { return url }
        return nil
    }
}
