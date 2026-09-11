import Foundation
import AppKit
import Combine

/// Retention policy for recorded clips.
struct ClipPolicy {
    /// Master switch. When false, clips are kept indefinitely (the pre-0.7.0
    /// behaviour) and neither rule below runs.
    var autoDelete: Bool
    /// How long a displaced clip lingers before being trashed, in seconds.
    var retention: TimeInterval
    /// Backstop cap on the total size of the clips folder.
    var maxTotalBytes: Int64

    static let `default` = ClipPolicy(
        autoDelete: true,
        retention: 120,
        maxTotalBytes: 250 * 1024 * 1024
    )
}

/// Owns the lifetime of recorded clips.
///
/// DubScribe exists to get audio *into the clipboard*, not to build a library,
/// so clips are transient by design. A clip moves to the Trash once it is no
/// longer useful, under three rules:
///
///  1. **Never delete the clip currently on the clipboard.** This is the
///     invariant the whole design hangs on. It was verified experimentally that
///     `NSPasteboard` keeps advertising a file URL after the target file is
///     gone (`canRead == true`, `fileExists == false`), so deleting the live
///     clip produces paste failures that look intermittent and inexplicable.
///  2. **Never delete the clip the in-app player has loaded**, or Reveal/Play
///     would point at a missing file.
///  3. **Only ever touch files we own** — `.wav`, our filename prefix, inside
///     our own clips directory (`FileManagerHelpers.isOwnedClip`).
///
/// Deletion goes through `trashItem`, never `removeItem`. A capture tool that
/// hard-deletes audio is one bug away from destroying something the user wanted,
/// and Trash keeps "Put Back" working.
@MainActor
final class ClipStore: ObservableObject {

    // MARK: - Published state (drives the settings UI)

    @Published private(set) var clipCount: Int = 0
    @Published private(set) var totalBytes: Int64 = 0

    /// Called when the set of clips changes, so the UI can refresh.
    var onClipsChanged: (() -> Void)?

    var policy: ClipPolicy = .default

    // MARK: - Protected clips

    /// The clip currently on the pasteboard.
    private(set) var clipboardClip: URL?
    /// The clip the audio player has loaded.
    private var playerClip: URL?

    /// When each clip stopped being pasteable. The retention clock, keyed by
    /// `identity(_:)` rather than by the raw URL — see that method.
    private var displacedAt: [URL: Date] = [:]

    /// Canonical identity for a clip.
    ///
    /// The same file reaches us under several spellings: our own
    /// `appendingPathComponent`, a directory listing, and the pasteboard (whose
    /// URL was authored by whichever app wrote it). Those spellings can differ —
    /// a symlinked path component (`/tmp` vs `/private/tmp`), a symlinked home
    /// directory, or a `..` segment — and a mismatch silently breaks any
    /// dictionary keyed by the raw `URL`. The effect is nasty and quiet: the
    /// retention clock is written under one key and read under another, so a
    /// displaced clip is deleted immediately rather than after its grace
    /// period. Key every identity map and comparison through here.
    ///
    /// Verified failing before this change: with the clips directory reached via
    /// the `/tmp` symlink, a displaced clip was trashed on the very first sweep.
    private static func identity(_ url: URL) -> URL {
        FileManagerHelpers.canonical(url)
    }

    private var timer: Timer?
    private var lastChangeCount: Int
    private var sweeping = false

    /// The instant the self-delete policy began (first launch of a version that
    /// has it).
    ///
    /// Clips recorded before this existed were captured by a version that never
    /// deleted anything and implicitly promised to keep them. Reclaiming them the
    /// moment someone upgrades would erase months of recordings they never agreed
    /// to lose, so pre-policy clips are exempt from the retention timer entirely.
    /// Only the size cap may touch them, and only when the folder genuinely
    /// exceeds it.
    private let policyStart: Date
    private static let policyStartKey = "clipPolicyStartDate"

    init() {
        lastChangeCount = ClipboardManager.changeCount

        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: Self.policyStartKey) as? Date {
            policyStart = stored
        } else {
            let now = Date()
            defaults.set(now, forKey: Self.policyStartKey)
            policyStart = now
        }
    }

    /// True for clips this app recorded under the current self-delete policy.
    /// Pre-0.7.0 clips are the user's own accumulation and are left alone.
    private func isSelfDeleting(_ url: URL) -> Bool {
        (creationDate(url) ?? .distantPast) >= policyStart
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard timer == nil else { return }
        // Two seconds: responsive enough to feel immediate, cheap enough to
        // ignore. This is the only recurring work the app does when idle.
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Events from the coordinator

    /// A clip has just been placed on the clipboard by us.
    func noteCopied(_ url: URL) {
        clipboardClip = url
        displacedAt[Self.identity(url)] = nil
        lastChangeCount = ClipboardManager.changeCount
        refreshStats()
        enforceSizeCap()
    }

    /// The player loaded a clip, or unloaded one (`nil`).
    func notePlayerLoaded(_ url: URL?) {
        playerClip = url
    }

    /// Called once at startup, after legacy migration.
    ///
    /// Seeds retention clocks from file creation dates so clips left over from
    /// a previous session are reclaimed. If the pasteboard still holds one of
    /// our clips — `writeObjects` writes eagerly, so it survives a quit — that
    /// one is re-protected rather than deleted.
    func reconcileOnLaunch() {
        lastChangeCount = ClipboardManager.changeCount

        if let live = ClipboardManager.clipboardClipURL(),
           FileManagerHelpers.isOwnedClip(live) {
            clipboardClip = live
        }

        let now = Date()
        for url in clipFiles() where !isProtected(url) && isSelfDeleting(url) {
            displacedAt[Self.identity(url)] = creationDate(url) ?? now
        }

        sweep()
    }

    // MARK: - Sweeping

    func sweep() {
        guard !sweeping else { return }
        sweeping = true
        defer { sweeping = false }

        refreshClipboardState()

        if policy.autoDelete {
            let now = Date()
            // Oldest first, so an over-cap folder reclaims the least useful
            // clips when several become eligible at once.
            for url in clipFiles().sorted(by: oldestFirst) {
                guard !isProtected(url) else { continue }
                // Never let the retention timer reclaim a clip the user recorded
                // before self-delete existed.
                guard isSelfDeleting(url) else { continue }
                let since = displacedAt[Self.identity(url)] ?? creationDate(url) ?? now
                if now.timeIntervalSince(since) >= policy.retention {
                    trash(url)
                }
            }
            enforceSizeCap()
        }

        refreshStats()
    }

    /// Detect that our clip is no longer the file URL on the pasteboard and
    /// start its retention clock.
    private func refreshClipboardState() {
        let count = ClipboardManager.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        let live = ClipboardManager.clipboardClipURL()

        if let current = clipboardClip,
           live.map(Self.identity) != Self.identity(current) {
            displacedAt[Self.identity(current)] = Date()
            clipboardClip = nil
        }

        // Another app (or the user) put one of our clips back on the
        // pasteboard — protect it again and clear its clock.
        if let live, FileManagerHelpers.isOwnedClip(live) {
            clipboardClip = live
            displacedAt[Self.identity(live)] = nil
        }
    }

    /// Size cap as the backstop for clips that are never displaced.
    ///
    /// Gated on `policy.autoDelete`: if the user has switched automatic
    /// deletion off, they have opted out of DubScribe managing disk for them,
    /// and silently deleting then would be the surprising behaviour.
    private func enforceSizeCap() {
        guard policy.autoDelete else { return }

        let files = clipFiles().sorted(by: oldestFirst)
        var total = files.reduce(Int64(0)) { $0 + size($1) }
        guard total > policy.maxTotalBytes else { return }

        for url in files {
            guard total > policy.maxTotalBytes else { break }
            guard !isProtected(url) else { continue }
            let bytes = size(url)
            trash(url)
            total -= bytes
        }
    }

    // MARK: - Protection

    private func isProtected(_ url: URL) -> Bool {
        let id = Self.identity(url)
        if let c = clipboardClip, Self.identity(c) == id { return true }
        if let p = playerClip, Self.identity(p) == id { return true }
        return false
    }

    // MARK: - Deletion

    private func trash(_ url: URL) {
        // Belt and braces: never touch a file we did not create, regardless of
        // how we got here.
        guard FileManagerHelpers.isOwnedClip(url) else {
            print("[DubScribe.ClipStore] Refusing to delete non-owned file \(url.lastPathComponent)")
            return
        }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            displacedAt[Self.identity(url)] = nil
            print("[DubScribe.ClipStore] Moved to Trash: \(url.lastPathComponent)")
            onClipsChanged?()
        } catch {
            print("[DubScribe.ClipStore] Could not trash \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Inventory

    /// Every clip we own, in no particular order.
    func clipFiles() -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: FileManagerHelpers.clipsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return [] }
        return entries.filter { FileManagerHelpers.isOwnedClip($0) }
    }

    /// Most recent clips first — for the UI.
    func recentClips(limit: Int = 5) -> [URL] {
        clipFiles().sorted(by: newestFirst).prefix(limit).map { $0 }
    }

    private func oldestFirst(_ a: URL, _ b: URL) -> Bool {
        (creationDate(a) ?? .distantPast) < (creationDate(b) ?? .distantPast)
    }

    private func newestFirst(_ a: URL, _ b: URL) -> Bool {
        (creationDate(a) ?? .distantPast) > (creationDate(b) ?? .distantPast)
    }

    private func creationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
    }

    private func size(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func refreshStats() {
        let files = clipFiles()
        clipCount = files.count
        totalBytes = files.reduce(Int64(0)) { $0 + size($1) }
    }
}
