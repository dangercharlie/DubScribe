import SwiftUI

/// Bundled release notes.
///
/// These live in the binary rather than being fetched. The README promises "no
/// network calls of any kind", and a release-notes window that phones home to
/// find out what changed would quietly break that promise — in a tool whose
/// whole pitch is that it stays on your machine. The cost is that notes ship
/// with the build, which is exactly right: they describe *this* build.
///
/// Add an entry for a release that changes something a user would notice. A
/// bug-fix release deliberately gets none: the popup appears only when the
/// running version has an entry, so leaving one out keeps the update silent
/// rather than re-showing old notes. Bug fixes are documented in CHANGELOG.md
/// instead, which is where anyone wanting the detail would look anyway.
///
/// Keep to the four items the window can show — more than that stops being
/// glanceable and turns into a changelog, which is what CHANGELOG.md is for.
enum ReleaseNotes {

    /// Notes for the version currently running, or nil if there are none.
    static var current: Release? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return all.first { $0.version == version }
    }

    static let all: [Release] = [v0_7_0]

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
