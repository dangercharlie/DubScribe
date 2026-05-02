import Foundation
import AppKit

enum FileManagerHelpers {

    /// Default clips directory: ~/Music/Hotkey Recorder/Clips/
    static var clipsDirectory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        return music
            .appendingPathComponent("Hotkey Recorder", isDirectory: true)
            .appendingPathComponent("Clips", isDirectory: true)
    }

    /// Ensures the clips directory exists, creating it if needed.
    static func ensureClipsDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: clipsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    /// Generates a timestamped WAV filename.
    static func newClipURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "Recording-\(timestamp).wav"
        return clipsDirectory.appendingPathComponent(filename)
    }

    /// Reveals a file in Finder.
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Reveals the clips directory in Finder.
    static func revealClipsFolder() {
        NSWorkspace.shared.open(clipsDirectory)
    }
}
