import Foundation
import AppKit

enum FileManagerHelpers {

    /// Clips directory: ~/Music/DubScribe/Clips/
    static var clipsDirectory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!
        return music
            .appendingPathComponent("DubScribe", isDirectory: true)
            .appendingPathComponent("Clips", isDirectory: true)
    }

    static func ensureClipsDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: clipsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    static func newClipURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let filename = "Recording-\(formatter.string(from: Date())).wav"
        return clipsDirectory.appendingPathComponent(filename)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealClipsFolder() {
        // Create the folder first if needed, then open it
        try? FileManager.default.createDirectory(
            at: clipsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        NSWorkspace.shared.open(clipsDirectory)
    }
}
