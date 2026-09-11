import AppKit
import Foundation

/// Copies a WAV file to the macOS clipboard so it can be pasted with ⌘V.
enum ClipboardManager {

    /// Places the file at `url` onto `NSPasteboard`.
    ///
    /// Writes **two** representations:
    ///
    /// 1. `public.file-url` — the primary form. Finder, Mail, Messages, Slack and
    ///    most native apps treat this as a real file attachment.
    /// 2. `public.utf8-plain-text` — the path, as a fallback. Some targets
    ///    (terminals, editors, plain text fields) cannot accept a file at all;
    ///    without this they would silently do nothing, which is the worst
    ///    possible outcome for a paste.
    ///
    /// Note there is no universal "audio" pasteboard type — `public.audio` is not
    /// reliably consumed — so the file URL is what actually makes this work.
    @discardableResult
    static func copyWAVFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let wroteFile = pasteboard.writeObjects([url as NSURL])

        // Add the text fallback. `addTypes` after `writeObjects` appends to the
        // same item rather than replacing the file URL.
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString(url.path, forType: .string)

        return wroteFile
    }

    /// The file URL currently on the pasteboard, if it points at one of our clips.
    /// Used by `ClipStore` to decide whether a clip is still pasteable.
    static func clipboardClipURL() -> URL? {
        guard let items = NSPasteboard.general.pasteboardItems else { return nil }
        for item in items {
            guard item.types.contains(.fileURL),
                  let raw = item.string(forType: .fileURL),
                  let url = URL(string: raw)
            else { continue }
            return url
        }
        return nil
    }

    /// Current pasteboard change count, used for cheap change detection.
    static var changeCount: Int { NSPasteboard.general.changeCount }
}
