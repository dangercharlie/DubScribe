import Foundation

enum RecordingTrigger: Equatable {
    case manual
    case pushHotkey
    case holdHotkey
}

enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date, trigger: RecordingTrigger)
    case processing
    case copied(URL)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
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

    var trigger: RecordingTrigger? {
        if case .recording(_, let t) = self { return t }
        return nil
    }

    var copiedURL: URL? {
        if case .copied(let url) = self { return url }
        return nil
    }

    var startedAt: Date? {
        if case .recording(let d, _) = self { return d }
        return nil
    }
}
