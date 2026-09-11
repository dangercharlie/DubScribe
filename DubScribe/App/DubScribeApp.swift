import SwiftUI
import AppKit

@main
struct DubScribeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        Window("DubScribe", id: "main") {
            ContentView()
                .environmentObject(coordinator)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let isRecording = coordinator.recordingState.isRecording

        Image(systemName: isRecording ? "mic.fill" : "mic")
            .foregroundStyle(isRecording ? Color.red : Color.primary)
    }
}

/// Quitting has to work while the settings sheet is up.
///
/// Settings is presented as a sheet, and a sheet puts the app into a state where
/// termination is *cancelled* rather than merely delayed. The Dock's Quit — and an
/// Apple Event quit — both come back as error `-128`, `userCanceledErr`, which is
/// exactly what a cancelled termination reports, so Quit simply did nothing at all
/// whenever Settings was on screen.
///
/// This was measured, not assumed: with no sheet presented the same Apple Event
/// quit exits cleanly, so the sheet is the cause rather than a symptom.
///
/// Ending any sheet first and then answering `.terminateNow` makes Quit behave the
/// way a background utility is expected to — immediately, whatever is on screen.
/// Nothing is lost by dropping the sheet, because settings are written as they are
/// changed rather than on dismissal.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in sender.windows where window.isSheet {
            window.sheetParent?.endSheet(window)
        }
        return .terminateNow
    }
}
