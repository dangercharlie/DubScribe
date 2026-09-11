import SwiftUI

/// Bundled release notes.
///
/// These live in the binary rather than being fetched. The README promises "no
/// network calls of any kind", and a release-notes window that phones home to
/// find out what changed would quietly break that promise — in a tool whose
/// whole pitch is that it stays on your machine. The cost is that notes ship
/// with the build, which is exactly right: they describe *this* build.
///
/// Add a new entry for each release. Keep the four items the window can show —
/// more than that stops being glanceable and turns into a changelog, which is
/// what CHANGELOG.md is for.
enum ReleaseNotes {

    /// Notes for the version currently running, or nil if there are none.
    static var current: Release? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return all.first { $0.version == version }
    }

    static let all: [Release] = [v0_7_1, v0_7_0]

    struct Release {
        let version: String
        let tagline: String
        let items: [Item]
    }

    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
    }

    private static let v0_7_1 = Release(
        version: "0.7.1",
        tagline: "A fix for recordings that opened Apple Music.",
        items: [
            Item(symbol: "music.note",
                 title: "\"Pause media\" stays out of Music",
                 detail: "With pause media on and nothing playing, finishing a recording could open Apple Music. It no longer does. Pausing and resuming music you are actually listening to works exactly as before."),

            Item(symbol: "speaker.slash",
                 title: "Nothing playing means nothing to pause",
                 detail: "DubScribe now checks whether any other app is producing sound before pausing. If none is, it leaves your audio alone instead of sending a play command into an empty room."),
        ]
    )

    private static let v0_7_0 = Release(
        version: "0.7.0",
        tagline: "Clips that clean up, a recording indicator, and a leaner app.",
        items: [
            Item(symbol: "arrow.triangle.2.circlepath",
                 title: "Clips clean up after themselves",
                 detail: "The clips folder is kept within a size budget, so recordings don't pile up. A clip still on your clipboard is never deleted, and anything removed goes to the Trash — Put Back still works."),

            Item(symbol: "waveform",
                 title: "A level indicator while recording",
                 detail: "A small panel at the top of the screen showing the app your clip will paste into, a live waveform of the input, and the elapsed time."),

            Item(symbol: "xmark",
                 title: "Voice activation is gone",
                 detail: "It was unreliable, and awkward with Bluetooth headsets. Hold or press a shortcut to record instead."),

            Item(symbol: "menubar.rectangle",
                 title: "DubScribe lives in the menu bar",
                 detail: "The main window is gone. Everything — recording, the last clip, playback, Settings — is in the menu bar, so there is nothing to switch to and no Dock icon."),
        ]
    )
}
