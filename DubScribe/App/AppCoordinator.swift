import Foundation
import Combine
import AVFoundation
import AppKit

/// Central coordinator — owns audio, hotkeys, clipboard, playback, retention.
@MainActor
final class AppCoordinator: ObservableObject {

    @Published var recordingState: RecordingState = .idle
    @Published var settings: AppSettings
    @Published var lastClipURL: URL?
    @Published var lastDuration: TimeInterval = 0

    /// Transient, user-facing message shown in the status area and then cleared.
    @Published var notice: String?

    let audioRecorder   = AudioRecorder()
    let audioPlayer     = AudioPlayer()
    let hotkeyManager   = HotkeyManager()
    let loginItemManager = LoginItemManager()
    let systemMediaController = SystemMediaController()
    let clipStore       = ClipStore()
    lazy var micTestManager = MicTestManager(audioRecorder: audioRecorder)
    lazy var recordingHUD = RecordingHUDController(recorder: audioRecorder)

    /// A second indicator used only to preview its appearance from Settings.
    ///
    /// Kept separate from the live one so that adjusting opacity in the middle of a
    /// recording can never disturb what is actually on screen.
    lazy var settingsPreviewHUD = RecordingHUDController(recorder: audioRecorder)

    /// Takes the preview back down a moment after the slider stops moving.
    private var previewDismissTask: Task<Void, Never>?

    /// Hard ceiling on a single recording. Hold-to-record plus a stuck key
    /// would otherwise fill the disk. Generous enough to never interrupt a
    /// real voice note.
    static let maxRecordingSeconds: TimeInterval = 300

    private var cancellables = Set<AnyCancellable>()
    private var pendingStartTask: Task<Void, Never>?
    private var pendingMediaPauseTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    /// The most recent app that was frontmost, excluding DubScribe itself.
    ///
    /// The indicator names where the clip will land, which only helps if it
    /// names the app the user is actually working in. Reading the frontmost app
    /// at the instant capture begins is not enough: pressing the shortcut while
    /// DubScribe's own window has focus would name DubScribe. Remembering the
    /// last *other* app keeps the answer useful in that case.
    private var lastForeignApp: NSRunningApplication?

    /// Retained so the observation could be torn down with the coordinator.
    private var activationObserver: NSObjectProtocol?

    /// Guards against stacking a second permission alert while one is up.
    private var isShowingMicrophoneAlert = false

    init() {
        // Settings first — policy below depends on them.
        switch AppSettings.loadResult() {
        case .loaded(let loaded):
            settings = loaded
        case .freshInstall:
            settings = .default
        case .recoveredFromCorrupt:
            // Do not silently pretend this was a fresh install.
            settings = .default
            notice = "Saved settings could not be read, so defaults were restored."
        }

        // One-time move of clips out of the pre-0.7.0 ~/Music location.
        let migrated = FileManagerHelpers.migrateLegacyClipsIfNeeded()

        wireAudio()
        wireHotkeys()

        // Register as a Now Playing client now rather than at the first pause.
        // MediaRemote's registration is asynchronous, so a command sent in the
        // same breath as registration is dropped: measured 3/6 that way against
        // 9/9 when the registration is made well in advance. Costs nothing here,
        // and it is what makes "Pause media playback" reliable rather than
        // sometimes-working.
        systemMediaController.prepareMediaControl()

        // Track the frontmost app so the indicator can name the destination.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.lastForeignApp = app }
        }

        clipStore.onClipsChanged = { [weak self] in
            self?.objectWillChange.send()
        }

        applySettings()

        clipStore.reconcileOnLaunch()
        clipStore.startMonitoring()

        if migrated > 0 {
            postNotice("Moved \(migrated) existing clip\(migrated == 1 ? "" : "s") into DubScribe's app storage.")
        }
    }

    // MARK: - Wiring

    private func wireAudio() {
        audioRecorder.onRecordingFinished = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in self.handleRecordingFinished(url: url) }
        }
    }

    private func wireHotkeys() {
        hotkeyManager.onHoldKeyDown = { [weak self] in
            self?.startRecording(trigger: .holdHotkey)
        }
        hotkeyManager.onHoldKeyUp = { [weak self] in
            guard self?.recordingState.trigger == .holdHotkey else { return }
            self?.stopRecording()
        }
        hotkeyManager.onPushKeyDown = { [weak self] in
            guard let self else { return }
            if self.recordingState.trigger == .pushHotkey {
                self.stopRecording()
            } else if !self.recordingState.isRecording {
                self.startRecording(trigger: .pushHotkey)
            }
        }
    }

    // MARK: - Recording Control

    func startRecording(trigger: RecordingTrigger = .manual) {
        guard !recordingState.isRecording else { return }

        // Stop mic test if active
        if micTestManager.state != .idle { micTestManager.reset() }

        switch PermissionHelpers.microphoneAuthorizationStatus {
        case .authorized:
            recordingState = .recording(startedAt: Date(), trigger: trigger)
            audioRecorder.selectedInputDeviceID = settings.selectedInputDeviceID
            let shouldMuteSystemAudio = settings.muteSystemAudioDuringRecording
            let shouldPauseMedia = settings.pauseMediaDuringRecording

            pendingStartTask?.cancel()
            pendingMediaPauseTask?.cancel()
            pendingStartTask = Task { @MainActor [weak self] in
                guard let self else { return }

                // Optional start cue. When it is enabled it must finish *before*
                // the microphone opens: it is audible through the speakers, so
                // playing it after the engine had started put it at the head of
                // every recording — a distinct transient about 140 ms in, at a
                // level comparable to speech. When it is switched off this
                // returns straight away and capture begins with no pre-roll.
                await self.playStartCueAndWait()

                guard !Task.isCancelled, self.recordingState.isRecording else { return }

                self.audioRecorder.startRecording()
                self.micTestManager.isRealRecordingActive = true

                // Visual feedback for the running take. On by default, and the
                // reason the start cue is now redundant enough to be opt-in.
                if self.settings.showRecordingHUD {
                    // Name the destination before showing it: the frontmost app
                    // is where the clip is about to be pasted, falling back to
                    // the last other app when DubScribe itself has focus.
                    let front = NSWorkspace.shared.frontmostApplication
                    let target = (front?.bundleIdentifier == Bundle.main.bundleIdentifier)
                        ? self.lastForeignApp
                        : front
                    self.recordingHUD.setTargetApplication(
                        name: target?.localizedName,
                        icon: target?.icon
                    )
                    self.recordingHUD.show()
                }
                // Capture starts now, so stamp the clock now rather than when the
                // shortcut was pressed.
                self.recordingState = .recording(startedAt: Date(), trigger: trigger)
                print("[DubScribe] Recording started (trigger=\(trigger))")

                self.scheduleAutoStop()

                if shouldMuteSystemAudio || shouldPauseMedia {
                    self.pendingMediaPauseTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard let self, !Task.isCancelled, self.recordingState.isRecording else { return }
                        if shouldMuteSystemAudio {
                            await self.systemMediaController.muteSystemAudio()
                        }
                        if shouldPauseMedia {
                            await self.systemMediaController.pauseMedia()
                        }
                    }
                }
            }

        case .notDetermined:
            PermissionHelpers.requestMicrophonePermission { [weak self] granted in
                if granted { self?.startRecording(trigger: trigger) }
                else {
                    self?.recordingState = .failed("Microphone access denied.")
                    self?.offerMicrophoneSettings()
                }
            }

        default:
            recordingState = .failed("Microphone access denied.")
            offerMicrophoneSettings()
        }
    }

    /// Offers a route to fix a missing microphone, at the moment it actually
    /// matters.
    ///
    /// The menu used to carry a permanent "Microphone Access Required" item. It
    /// was removed because a row that is always there for a situation that is
    /// almost never true is just clutter — you learn to ignore it, and it casts
    /// doubt on a working app. The help belongs at the moment you press record
    /// and nothing happens, which is the only time it is information rather than
    /// noise.
    private func offerMicrophoneSettings() {
        // Never stack alerts: a second press while one is up would add another.
        guard !isShowingMicrophoneAlert else { return }
        isShowingMicrophoneAlert = true
        defer { isShowingMicrophoneAlert = false }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "DubScribe needs microphone access"
        alert.informativeText = """
            Without it, recordings are silent and nothing reaches your clipboard.

            You can grant access in System Settings → Privacy & Security → Microphone.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            PermissionHelpers.openMicrophoneSettings()
        }
    }


    func stopRecording() {
        guard recordingState.isRecording else { return }
        pendingStartTask?.cancel()
        pendingStartTask = nil
        pendingMediaPauseTask?.cancel()
        pendingMediaPauseTask = nil
        autoStopTask?.cancel()
        autoStopTask = nil

        let recorderWasActive = audioRecorder.isRecording
        recordingState = .processing
        lastDuration = audioRecorder.recordingDuration

        guard recorderWasActive else {
            recordingState = .idle
            return
        }

        audioRecorder.stopRecording()
        micTestManager.isRealRecordingActive = false

        let shouldRestoreSystemAudio = settings.muteSystemAudioDuringRecording
        let shouldResumeMedia = settings.pauseMediaDuringRecording
        if shouldRestoreSystemAudio || shouldResumeMedia {
            let delay = settings.mediaResumeDelay
            let systemMediaController = systemMediaController
            Task {
                if shouldRestoreSystemAudio {
                    await systemMediaController.restoreSystemAudio()
                }
                // Resume media with configurable crossover delay.
                // This is stop-side only; it should not affect recording startup.
                if shouldResumeMedia {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    await systemMediaController.resumeMedia()
                }
            }
        }

        playSound(named: "Pop")
    }

    /// Watchdog so a forgotten recording cannot run forever.
    private func scheduleAutoStop() {
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor [weak self] in
            let seconds = UInt64(AppCoordinator.maxRecordingSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: seconds)
            guard let self, !Task.isCancelled, self.recordingState.isRecording else { return }
            self.stopRecording()
            self.postNotice("Stopped at the \(Int(AppCoordinator.maxRecordingSeconds / 60))-minute limit.")
        }
    }

    private func handleRecordingFinished(url: URL?) {
        guard let url else {
            // Nothing usable was captured, so take the indicator down rather than
            // confirming a clip that does not exist.
            recordingHUD.hide()
            recordingState = .failed(audioRecorder.lastError ?? "Unknown recording error.")
            return
        }

        // Discard a clip that captured nothing rather than putting silence on
        // the clipboard — a silent paste looks like the app is broken.
        if audioRecorder.lastPeakLevel < 0.002 {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            recordingHUD.hide()
            recordingState = .failed("Nothing was captured — check the input device.")
            postNotice("Nothing was captured. Check the input device in Settings.")
            return
        }

        let success = ClipboardManager.copyWAVFile(url)
        if success {
            lastClipURL = url
            recordingState = .copied(url)
            clipStore.noteCopied(url)
            audioPlayer.load(url: url)
            clipStore.notePlayerLoaded(url)
            // Only confirm once the clip is genuinely on the clipboard.
            if settings.showRecordingHUD { recordingHUD.confirmCopied() }
        } else {
            recordingHUD.hide()
            recordingState = .failed("Could not copy file to clipboard.")
        }
    }

    // MARK: - Last clip

    func revealLastClip() {
        guard let url = lastClipURL else { return }
        FileManagerHelpers.revealInFinder(url)
    }

    func revealClipsFolder() { FileManagerHelpers.revealClipsFolder() }

    /// Put the most recent clip back on the clipboard without re-recording.
    /// Cheap, and it rescues the common "I pasted into the wrong window" case.
    @discardableResult
    func copyLastClipAgain() -> Bool {
        guard let url = lastClipURL,
              FileManager.default.fileExists(atPath: url.path) else {
            postNotice("The last clip is no longer available.")
            return false
        }
        let ok = ClipboardManager.copyWAVFile(url)
        if ok {
            clipStore.noteCopied(url)
            recordingState = .copied(url)
            postNotice("Copied to clipboard.")
        }
        return ok
    }

    // MARK: - Settings

    func applySettings() {
        // Sanitise stored hotkeys before registering them.
        //
        // A pre-0.7.0 build could persist a shortcut with no modifier — a bare
        // "R", say — which `RegisterEventHotKey` accepts and which then swallows
        // that key system-wide. Anyone already in that state gets repaired here
        // rather than having it re-armed on every launch.
        var repaired: String?
        if let reason = settings.holdHotkey.rejectionReason {
            settings.holdHotkey = .defaultHoldHotkey
            repaired = reason
        }
        if let reason = settings.pushHotkey.rejectionReason {
            settings.pushHotkey = .defaultPushHotkey
            repaired = reason
        }
        if let repaired {
            postNotice("Shortcut reset to default — \(repaired)")
        }

        // Guard against nonsense values from a hand-edited or corrupt blob.
        let capBytes = Int64(max(10, settings.maxClipsSizeMB) * 1024 * 1024)
        clipStore.policy = ClipPolicy(
            autoDelete: settings.autoDeleteClips,
            maxTotalBytes: capBytes
        )

        settings.save()
        hotkeyManager.configure(holdHotkey: settings.holdHotkey, pushHotkey: settings.pushHotkey)
        micTestManager.threshold = settings.micTestThreshold

        // With voice activation gone the microphone is no longer held open
        // permanently. It is only hot during a real recording or an explicit
        // mic test — which also means no standing orange indicator.
        if micTestManager.state == .idle, !recordingState.isRecording {
            audioRecorder.stopLevelMonitoring()
        }

        // Turning the indicator off should take effect immediately, even if it is
        // currently on screen mid-recording.
        updateHUDAppearance()
    }

    /// Appearance-only update for the indicator, safe to call on every slider
    /// tick.
    ///
    /// Deliberately separate from `applySettings()`, which re-registers global
    /// hotkeys and writes to disk — running that dozens of times a second while a
    /// slider is dragged would be both wasteful and disruptive.
    func updateHUDAppearance() {
        recordingHUD.setBackdropOpacity(settings.hudOpacity)
        // The preview is a separate indicator, so it has to be told as well.
        // Without this it keeps whatever opacity it was last shown with, and the
        // slider appears to do nothing while the preview is up — which is exactly
        // when the user is watching it.
        settingsPreviewHUD.setBackdropOpacity(settings.hudOpacity)
        if !settings.showRecordingHUD { recordingHUD.hide() }
    }

    /// Show the indicator as a still preview and restart the clock that takes it
    /// away again.
    ///
    /// Called on every change to the opacity, so a continuous drag keeps pushing
    /// the dismissal back and the preview stays up for as long as the user is
    /// adjusting it — and lingers a moment afterwards, which is the point: the
    /// last thing they did was let go, and they need to see the result of it.
    func previewHUDAppearance() {
        guard settings.showRecordingHUD else { return }
        // Set the opacity before showing, so the first frame is already the value
        // being dragged to rather than the controller's default.
        settingsPreviewHUD.setBackdropOpacity(settings.hudOpacity)
        settingsPreviewHUD.showPreview()

        previewDismissTask?.cancel()
        previewDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            settingsPreviewHUD.hidePreview()
        }
    }

    /// Take the preview away now — used when Settings closes, so the indicator
    /// cannot outlive the window it belongs to.
    func endPreviewHUDAppearance() {
        previewDismissTask?.cancel()
        previewDismissTask = nil
        settingsPreviewHUD.hidePreview()
    }

    func resetHoldHotkey() { settings.holdHotkey = .defaultHoldHotkey; applySettings() }
    func resetPushHotkey() { settings.pushHotkey = .defaultPushHotkey; applySettings() }

    // MARK: - Notices

    func postNotice(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    // MARK: - Sounds

    private func playSound(named name: String) {
        guard settings.playSounds else { return }
        guard let sound = NSSound(named: name) else { return }
        // Play the cue quietly. `NSSound` plays at the full system output volume,
        // which is startling when your output is turned up — and considerably
        // worse over a Bluetooth headset, which macOS has usually pushed into
        // narrowband call mode because we just opened the microphone.
        sound.volume = Self.cueVolume
        sound.play()
    }

    /// How loud the start/stop cue plays, as a fraction of system output volume.
    ///
    /// Reported by a user as "the beep very loud even when im using the
    /// integrated mic" — the cue is unrelated to the chosen input, so the only
    /// fix is to stop playing it at full output volume.
    private static let cueVolume: Float = 0.35

    /// How long to wait after the start cue before opening the microphone.
    ///
    /// Deliberately *not* derived from `NSSound.duration`. These system sounds
    /// carry long silent tails: `Tink` reports 0.564 s but is only audible for
    /// its first ~40 ms, and `Pop` reports 1.627 s but is audible for ~0.2 s.
    /// Waiting on the reported duration would add two thirds of a second of lag
    /// to every recording for no benefit.
    ///
    /// 0.2 s comfortably covers the cue plus its room decay, and is short enough
    /// that pressing a shortcut still feels immediate.
    private static let startCueLeadTime: TimeInterval = 0.2

    /// Play the start cue and wait for it to finish before returning.
    ///
    /// Used on the *start* path only, and only when the opt-in start cue is
    /// enabled: the microphone is about to open, so anything still sounding would
    /// be recorded. With the cue switched off there is no pre-roll delay at all,
    /// so capture starts immediately — which is the point of making it optional.
    ///
    /// The stop path deliberately uses the non-blocking `playSound`, because by
    /// then the microphone is already closed.
    private func playStartCueAndWait() async {
        guard settings.playStartCue, let sound = NSSound(named: "Tink") else {
            // Keep the small deferral the start path always had, so the UI state
            // settles before capture begins.
            try? await Task.sleep(nanoseconds: 16_000_000)
            return
        }
        sound.volume = Self.cueVolume
        sound.play()
        try? await Task.sleep(nanoseconds: UInt64(Self.startCueLeadTime * 1_000_000_000))
    }

    // MARK: - Permissions

    var allPermissionsGranted: Bool {
        // Carbon hotkeys don't need Accessibility — only mic matters
        PermissionHelpers.isMicrophoneAuthorized
    }
}
