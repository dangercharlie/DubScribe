import Foundation
import AppKit

enum FileManagerHelpers {

    // MARK: - Locations

    /// Where clips live.
    ///
    /// Clips are deliberately transient: DubScribe moves each one to the Trash
    /// once it is no longer pasteable, so this directory behaves like a cache
    /// rather than a user document library. Application Support is the honest
    /// home for that.
    ///
    /// Pre-0.7.0 builds wrote to `~/Music/DubScribe/Clips/`. Those clips are
    /// migrated here on first launch — see `migrateLegacyClipsIfNeeded()`.
    static var clipsDirectory: URL {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            // `applicationSupportDirectory` is always present on macOS. Fall
            // back rather than force-unwrapping and crashing.
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("DubScribe", isDirectory: true)
                .appendingPathComponent("Clips", isDirectory: true)
        }
        return base
            .appendingPathComponent("DubScribe", isDirectory: true)
            .appendingPathComponent("Clips", isDirectory: true)
    }

    /// The pre-0.7.0 clips location. Retained only so existing clips can be
    /// migrated out of it.
    static var legacyClipsDirectory: URL {
        guard let music = FileManager.default
            .urls(for: .musicDirectory, in: .userDomainMask).first
        else {
            return clipsDirectory   // nothing to migrate from
        }
        return music
            .appendingPathComponent("DubScribe", isDirectory: true)
            .appendingPathComponent("Clips", isDirectory: true)
    }

    /// Prefix for clips we created. Used to scope destructive operations so we
    /// only ever touch our own files.
    static let clipFilenamePrefix = "Recording-"

    // MARK: - Directory

    static func ensureClipsDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: clipsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // MARK: - Naming

    static func newClipURL(on date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let stamp = formatter.string(from: date)

        var candidate = clipsDirectory
            .appendingPathComponent("\(clipFilenamePrefix)\(stamp).wav")

        // Two recordings can land in the same second — a quick push-then-hold,
        // or a repeat. Without uniquing the second file silently overwrites the
        // first, which is exactly the kind of data loss that is hardest to
        // notice. Probe for a free name instead.
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = clipsDirectory
                .appendingPathComponent("\(clipFilenamePrefix)\(stamp)-\(suffix).wav")
            suffix += 1
        }
        return candidate
    }

    /// True for files this app owns: `.wav` inside our clips directory, named
    /// with our prefix. Guards every delete path.
    ///
    /// Compares canonicalised paths (symlinks resolved) because the same file is
    /// reached under different spellings — our own URL, a directory listing, and
    /// the pasteboard's URL, which was authored by whichever app wrote it.
    static func isOwnedClip(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav" else { return false }
        guard url.lastPathComponent.hasPrefix(clipFilenamePrefix) else { return false }
        return canonical(url.deletingLastPathComponent()) == canonical(clipsDirectory)
    }

    /// Canonical form of a path for identity comparisons. See `isOwnedClip`.
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    // MARK: - Migration

    /// Move clips from the pre-0.7.0 `~/Music` location into Application
    /// Support. Idempotent; safe to call on every launch.
    ///
    /// This *moves* rather than copies, so the old folder stops growing. The
    /// old directory is only removed once it is empty, so anything the user put
    /// there themselves is left alone.
    @discardableResult
    static func migrateLegacyClipsIfNeeded() -> Int {
        let fm = FileManager.default
        let legacy = legacyClipsDirectory

        guard legacy.standardizedFileURL != clipsDirectory.standardizedFileURL,
              fm.fileExists(atPath: legacy.path),
              let entries = try? fm.contentsOfDirectory(
                  at: legacy, includingPropertiesForKeys: nil)
        else { return 0 }

        try? ensureClipsDirectoryExists()

        var moved = 0
        for src in entries where src.pathExtension.lowercased() == "wav" {
            let stem = src.deletingPathExtension().lastPathComponent
            var dest = clipsDirectory.appendingPathComponent(src.lastPathComponent)

            var suffix = 2
            while fm.fileExists(atPath: dest.path) {
                dest = clipsDirectory.appendingPathComponent("\(stem)-\(suffix).wav")
                suffix += 1
            }

            do {
                try fm.moveItem(at: src, to: dest)
                moved += 1
            } catch {
                print("[DubScribe] Could not migrate \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }

        // Only tidy up empty directories — never delete content we did not read.
        if let remaining = try? fm.contentsOfDirectory(atPath: legacy.path), remaining.isEmpty {
            try? fm.removeItem(at: legacy)
            let parent = legacy.deletingLastPathComponent()
            if let p = try? fm.contentsOfDirectory(atPath: parent.path), p.isEmpty {
                try? fm.removeItem(at: parent)
            }
        }

        if moved > 0 {
            print("[DubScribe] Migrated \(moved) clip(s) to Application Support")
        }
        return moved
    }

    // MARK: - Reveal

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealClipsFolder() {
        try? ensureClipsDirectoryExists()
        NSWorkspace.shared.open(clipsDirectory)
    }
}
