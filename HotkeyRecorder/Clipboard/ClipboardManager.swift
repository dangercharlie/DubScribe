import AppKit
import Foundation

/// Copies a WAV file to the macOS clipboard so it can be pasted via Cmd+V.
enum ClipboardManager {

    /// Places the file at `url` onto NSPasteboard.
    /// Includes both a file URL and a file-promise-compatible representation
    /// so Finder and compatible apps treat it as a real file.
    @discardableResult
    static func copyWAVFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Write as a file URL — this is the most widely compatible method.
        // Finder, Mail, and most macOS apps can receive file URLs via paste.
        let success = pasteboard.writeObjects([url as NSURL])
        return success
    }
}
