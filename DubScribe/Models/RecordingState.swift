import Foundation

enum RecordingTrigger: Equatable {
    case manual
    case pushHotkey
    case holdHotkey
    case voiceActivation
}

enum RecordingState: Equatable {
    case idle
    case listeningForVoice          // voice activation mode active, waiting
    case recording(startedAt: Date, trigger: RecordingTrigger)
    case processing
    case copied(URL)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .listeningForVoice:
            return "Listening for voice…"
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
