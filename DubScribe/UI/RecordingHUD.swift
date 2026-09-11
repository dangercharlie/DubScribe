import SwiftUI
import AppKit

/// Single source of truth for the indicator's size, shared by the AppKit panel
/// and the SwiftUI content it hosts.
enum RecordingHUDMetrics {
    /// Wide enough for the destination app's name beside its icon, and tall
    /// enough for two rows: the destination line, then the dot matrix under it.
    ///
    /// This is the *window* size and never changes. Collapsing the indicator
    /// shrinks only the content inside it.
    static let size = NSSize(width: 300, height: 80)

    /// What the indicator collapses to once capture stops.
    ///
    /// The matrix is live data, so the instant a recording ends it is stale, and
    /// holding a frozen trace on screen for the whole confirmation is what made
    /// stopping feel sluggish. Dropping the matrix and closing the panel up
    /// around the confirmation line is the difference between the indicator
    /// standing down and the indicator being left switched on.
    static let compactHeight: CGFloat = 46

    static func contentHeight(for state: RecordingHUDState) -> CGFloat {
        switch state {
        case .recording: return size.height
        case .copied:    return compactHeight
        }
    }
}

/// What the on-screen indicator is currently showing.
enum RecordingHUDState: Equatable {
    case recording
    case copied
}

/// Drives the indicator's state.
///
/// Kept separate from `AudioRecorder` because the HUD outlives capture: it holds
/// a brief "Copied" confirmation after recording has already stopped.
@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var state: RecordingHUDState = .recording

    /// Opacity of the backdrop only — never the waveform or text, which must stay
    /// fully legible however transparent the panel gets.
    @Published var backdropOpacity: Double = 0.7

    /// Where the clip will land: the app that was frontmost when capture began.
    ///
    /// Shown in the indicator so the destination is visible *before* pasting —
    /// the same promise as the clipboard behaviour, made one step earlier. Both
    /// are optional because there is not always a foreign app to name (a
    /// hotkey pressed while DubScribe itself is frontmost, for instance).
    @Published var targetAppName: String?
    @Published var targetAppIcon: NSImage?
}

/// A panel that can never become key or main.
///
/// This override is the whole reason the indicator is safe to show: without it,
/// displaying an overlay activates the app and steals focus from whatever the
/// user is typing into — the classic heads-up-display failure mode.
final class RecordingHUDWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A floating level indicator shown while a clip is being captured.
///
/// Deliberately an AppKit panel rather than a SwiftUI window, because it must:
///   * never take focus (`.nonactivatingPanel` plus the overrides above),
///   * float above everything, including full-screen apps and every Space,
///   * ignore the mouse entirely, so it can never swallow a click.
///
/// It is deliberately *not* excluded from screen capture. An earlier version
/// set `sharingType = .none` to keep the indicator out of screen shares, but
/// that is an absolute exclusion — it also blocks the user's own screenshots,
/// so the feature could never be shown, demoed, or reported on. The default
/// (`readOnly`) is what other menu-bar indicators do.
@MainActor
final class RecordingHUDController {
    private var panel: RecordingHUDWindow?
    private let model = RecordingHUDModel()
    private let recorder: AudioRecorder
    private var dismissTask: Task<Void, Never>?

    /// Held while the indicator is on screen to keep App Nap from throttling it.
    ///
    /// This matters more than it looks. DubScribe is an accessory app that is
    /// almost never frontmost while recording — that is the entire point of it —
    /// and an app that is neither frontmost nor focused is exactly what macOS
    /// slows down. The indicator's animation is driven by the display link, so
    /// being throttled shows up directly as a low frame rate: the trace stutters
    /// and new data arrives in lumps. Declaring the work user-initiated for as
    /// long as the panel is up is what keeps it smooth.
    private var activityToken: NSObjectProtocol?

    /// How long the "Copied" confirmation stays up before the indicator leaves.
    private static let confirmationSeconds: TimeInterval = 1.3

    /// Clearance below the menu bar.
    private static let topInset: CGFloat = 14

    init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Update how transparent the backdrop is. Safe to call at any time; takes
    /// effect immediately if the indicator is on screen.
    func setBackdropOpacity(_ value: Double) {
        model.backdropOpacity = min(max(value, 0.0), 1.0)
    }

    /// Name the app this clip is destined for. Called when capture begins, so
    /// the indicator shows where the text will land before the user pastes.
    func setTargetApplication(name: String?, icon: NSImage?) {
        model.targetAppName = name
        model.targetAppIcon = icon
    }

    /// Show the indicator and begin tracking the live level.
    func show() {
        dismissTask?.cancel()
        dismissTask = nil
        model.state = .recording

        let panel = self.panel ?? makePanel()
        self.panel = panel
        reposition(panel)
        beginPreventingThrottle()
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the entire
        // point is that this never activates DubScribe nor disturbs the user's
        // focus in whatever app they are actually working in.
        panel.orderFrontRegardless()
    }

    /// Swap to the "Copied" confirmation, then take the indicator away.
    func confirmCopied() {
        guard panel != nil else { return }
        model.state = .copied
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.confirmationSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.endPreventingThrottle()
        }
    }

    /// Take the indicator down immediately — used when the setting is switched
    /// off, or when a recording is abandoned.
    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        endPreventingThrottle()
    }

    // MARK: - Throttle suppression

    /// Claim user-initiated work so the display link keeps running at full rate
    /// while the indicator is up, even though DubScribe is in the background.
    ///
    /// `AllowingIdleSystemSleep` is the whole point of this variant. Plain
    /// `.userInitiated` is defined as `0x00FFFFFF | NSActivityIdleSystemSleepDisabled`,
    /// so it also stops the Mac idle-sleeping for as long as a recording runs — a
    /// real side effect for what is only a decorative animation, and one the
    /// Foundation header explicitly warns about. Suppressing App Nap is what this
    /// needs; holding sleep off is not.
    ///
    /// `.latencyCritical` was dropped deliberately. It is the strongest claim in
    /// the API — `.userInitiated | .latencyCritical` is literally
    /// `NSActivityUserInteractive` — and an A/B measurement of the assertion
    /// found no benefit from the assertion at all, let alone the stronger form.
    /// Claiming high-priority scheduling that nothing has shown a need for is
    /// exactly the kind of cost a background utility should not carry.
    ///
    /// The assertion itself stays rather than being deleted, because in this form
    /// its cost is effectively zero and it covers the one configuration that
    /// could not be measured: every window occluded.
    private func beginPreventingThrottle() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Animating the recording indicator"
        )
    }

    private func endPreventingThrottle() {
        guard let activityToken else { return }
        ProcessInfo.processInfo.endActivity(activityToken)
        self.activityToken = nil
    }

    // MARK: - Panel construction

    private func makePanel() -> RecordingHUDWindow {
        let hosting = NSHostingView(rootView: RecordingHUDView(recorder: recorder, model: model))
        hosting.frame = NSRect(origin: .zero, size: RecordingHUDMetrics.size)

        let panel = RecordingHUDWindow(
            contentRect: NSRect(origin: .zero, size: RecordingHUDMetrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        // Above normal windows, so it stays visible over a full-screen editor.
        panel.level = .statusBar
        // Follow the user everywhere: every Space, and over full-screen apps.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        // Click-through: the indicator must never intercept a click.
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        // It is a decorative animation, so VoiceOver should skip it entirely
        // rather than announce a meaningless graphic.
        //
        // Both calls are needed: `NSHostingView` overrides
        // `isAccessibilityElement`, so setting that alone was verified to still
        // report `true`. Hiding the subtree is what actually keeps VoiceOver off
        // it — the menu-bar item carries the accessible state instead.
        hosting.setAccessibilityElement(false)
        hosting.setAccessibilityHidden(true)
        return panel
    }

    /// Top-centre, just below the menu bar — where macOS puts the volume HUD.
    ///
    /// `visibleFrame` already excludes the menu bar, which also keeps the panel
    /// clear of the camera housing on notched displays. The primary screen is
    /// used deliberately: it is the one carrying the menu bar, and therefore the
    /// one a system HUD would appear on.
    private func reposition(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - Self.topInset
        ))
    }
}

// MARK: - SwiftUI content

struct RecordingHUDView: View {
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject var model: RecordingHUDModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        hudContent
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    // A slightly stronger edge than before: the more transparent
                    // the backdrop, the more the panel needs its bounds defined.
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            // The window is built once at the full size and never resized, so
            // collapsing the indicator cannot make the panel jump or tear.
            // Pinning the content to the top keeps the indicator's top edge —
            // the edge the eye is actually anchored to, just under the menu bar
            // — perfectly still while the bottom edge rises.
            .frame(width: RecordingHUDMetrics.size.width,
                   height: RecordingHUDMetrics.size.height,
                   alignment: .top)
    }

    /// The frosted backdrop.
    ///
    /// The material stays at full strength; the opacity setting drives a *tint*
    /// layer over it. Fading the material itself — which is what this used to do
    /// — trades away the blur rather than the darkness: as the value fell, the
    /// unblurred desktop behind showed through sharper and sharper, so the panel
    /// read as dirty glass instead of frosted glass. Keeping the blur constant
    /// and varying the tint means the panel stays properly frosted at every
    /// setting, which is how native HUDs behave.
    private var backdrop: some View {
        ZStack {
            HUDVisualEffectView(material: .hudWindow,
                                blendingMode: .behindWindow,
                                alpha: Self.materialAlpha(for: model.backdropOpacity))
            Color.black.opacity(Self.tintStrength(for: model.backdropOpacity))
        }
    }

    /// How strong the black tint over the frost is, at the top of the range.
    ///
    /// This used to be `value * 0.45` across a 0.15...1.0 slider, which meant the
    /// darkest setting was a near-solid slab. Measured against the old scale, the
    /// top of the new range is exactly where the old *minimum* sat
    /// (`0.15 * 0.45`), so what used to be the most transparent the indicator
    /// could get is now the most opaque it can get.
    private static let maxTint: Double = 0.15 * 0.45

    private static func tintStrength(for opacity: Double) -> Double {
        min(max(opacity, 0), 1) * maxTint
    }

    /// The frost is faded, not just de-tinted, below the top of the range.
    ///
    /// A tint can only ever *add* darkness, so once the tint has been turned all
    /// the way down there is nothing left to give — and a tint range that small
    /// would leave the slider doing almost nothing. Fading the effect view itself
    /// is the only lever that reaches past the material, so the lower half of the
    /// slider spends it: at the top the frost is untouched (reproducing the old
    /// minimum exactly), and at the bottom it is composited at 60%, which lets the
    /// desktop through in a way no amount of tinting can.
    private static func materialAlpha(for opacity: Double) -> Double {
        0.6 + 0.4 * min(max(opacity, 0), 1)
    }

    /// Everything inside the HUD, without the material backdrop.
    ///
    /// Split out purely so it can be rendered to an image for verification:
    /// `ImageRenderer` cannot rasterise `NSVisualEffectView` (it produces garbage
    /// colours), so the layout and content are checked this way while the material
    /// itself is confirmed in the running app.
    var hudContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The top row names the destination. The recording dot and the timer
            // ride along up here so the level row gets the full width beneath it.
            HStack(spacing: 7) {
                statusIcon
                if let icon = model.targetAppIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 17, height: 17)
                }
                Text(model.targetAppName ?? Self.clipboardFallbackName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                elapsed
            }
            // The moment capture stops the trace is history, so it goes. Only the
            // confirmation row is left, and the panel closes up around it.
            if model.state == .recording {
                dotMatrix
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: RecordingHUDMetrics.size.width,
               height: RecordingHUDMetrics.contentHeight(for: model.state))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.state)
    }

    /// Shown when there is no other app to name. The clip still has a
    /// destination — it is the clipboard, not an application.
    private static let clipboardFallbackName = "Clipboard"

    @ViewBuilder
    private var statusIcon: some View {
        switch model.state {
        case .copied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 9, height: 9)
                // Repeat-forever animation is skipped entirely when the user has
                // asked for reduced motion; the dot simply stays solid.
                .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.3))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
    }

    /// The scrolling dot matrix.
    ///
    /// A grid of dots — thirteen rows deep, so the trace has real vertical detail
    /// rather than reading as a single strip. Each column is one time bin, and
    /// its amplitude lights the dots outward from the centre row, mirroring the
    /// waveform above and below the axis. Silence therefore draws a flat line of
    /// single dots through the middle, exactly as a waveform should.
    ///
    /// The scroll is driven by `TimelineView(.animation)`, so positions are
    /// recomputed from the clock every frame. Audio only arrives about ten times
    /// a second, and placing columns by *age* rather than by array index is what
    /// turns that into continuous motion: two frames a frame apart produce
    /// positions a frame apart, with no quantisation to bin boundaries.
    private var dotMatrix: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let bins = recorder.waveform

                // Draw slightly behind real time. A single audio callback hands
                // over a whole buffer's worth of bins at once — about six every
                // 100 ms — and drawing them the moment they arrive is what makes
                // the trace advance in visible 10 Hz steps. Holding them back by
                // a little more than one callback means each bin is released when
                // its own moment arrives instead, so new data flows in at the
                // rate it was captured rather than in bursts.
                let now = timeline.date.timeIntervalSinceReferenceDate - Self.revealDelay

                let columns = DotMatrixGeometry.visibleColumns(
                    binCount: bins.count,
                    newest: recorder.waveformEnd,
                    interval: recorder.waveformBinInterval,
                    now: now,
                    width: size.width
                )

                let pitch = Self.dotSize + Self.dotGap
                let top = (size.height - Self.matrixHeight) / 2
                let centreRow = Self.matrixRows / 2
                let centreY = top + CGFloat(centreRow) * pitch

                guard !columns.isEmpty else {
                    // Silence — and equally the moment before the first buffer
                    // arrives, which the reveal delay stretches to about 220 ms.
                    //
                    // Drawing the flat axis rather than nothing is not merely
                    // cosmetic, and the reason is not obvious: an *empty* Canvas
                    // is pathological. Measured at ~108% CPU against ~30% when it
                    // draws, because SwiftUI appears to keep re-evaluating a
                    // display list that produces nothing at all. A flat line is
                    // also, conveniently, exactly what silence looks like on a
                    // waveform.
                    var x: CGFloat = 0
                    while x < size.width {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: centreY,
                                                   width: Self.dotSize, height: Self.dotSize)),
                            with: .color(Color.primary.opacity(Self.edgeFade(x, width: size.width)))
                        )
                        x += pitch
                    }
                    return
                }

                for column in columns {
                    // Outward from the centre: how many dots the amplitude lights.
                    // The settle term springs the column up to its height rather
                    // than stamping it there.
                    let amplitude = Self.displayLevel(bins[column.index])
                        * Self.elasticSettle(CGFloat(column.age / Self.settleSeconds))
                    let reach = Int((amplitude * CGFloat(centreRow)).rounded())
                    let fade = Self.edgeFade(column.x, width: size.width)

                    for row in (centreRow - reach)...(centreRow + reach) {
                        let rect = CGRect(
                            x: column.x,
                            y: top + CGFloat(row) * pitch,
                            width: Self.dotSize,
                            height: Self.dotSize
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color.primary.opacity(fade))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.matrixHeight)
    }

    /// Geometry of the matrix: fine round dots, roughly square cells.
    ///
    /// Thirteen rows, not two: the vertical detail is the whole point of a dot
    /// matrix, and since the waveform mirrors around the centre row an odd row
    /// count gives a clean axis with an equal number of steps above and below it.
    private static let matrixRows = 13
    private static let dotSize: CGFloat = 1.6
    private static let dotGap: CGFloat = 1.1
    private static var matrixHeight: CGFloat {
        CGFloat(matrixRows) * dotSize + CGFloat(matrixRows - 1) * dotGap
    }

    /// How far behind real time the matrix is drawn, so that a buffer's worth of
    /// bins can be released one at a time. A little more than the measured
    /// ~100 ms callback interval, with margin for jitter.
    private static let revealDelay: TimeInterval = 0.12

    /// How long a column takes to spring into its final height.
    private static let settleSeconds: TimeInterval = 0.15

    /// Ease a column up to its height instead of snapping to it.
    ///
    /// `easeOutBack` deliberately overshoots before settling, and that overshoot
    /// is where the elasticity comes from: a new column rises past its target and
    /// eases back, so the trace reads as springy rather than stamped on.
    private static func elasticSettle(_ t: CGFloat) -> CGFloat {
        guard t < 1 else { return 1 }
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        let p = t - 1
        return 1 + c3 * p * p * p + c1 * p * p
    }

    /// Soften both edges so columns fade in and out instead of appearing and
    /// vanishing at full strength.
    ///
    /// This is the part that stops the scroll reading as clunky: a hard entry at
    /// one edge and a hard exit at the other were the problem, not the motion
    /// itself.
    private static func edgeFade(_ x: CGFloat, width: CGFloat) -> Double {
        let ramp: CGFloat = 10
        let fromLeft = min(max(x / ramp, 0), 1)
        let fromRight = min(max((width - x) / ramp, 0), 1)
        return Double(min(fromLeft, fromRight))
    }

    /// Map RMS onto a 0…1 display level with a dB curve.
    ///
    /// The floor matters more here than it looks. At -55 dB — the value the old
    /// bar trace used — ordinary speech landed around 0.8, so nearly every
    /// column sat at full height and the matrix read as a solid blob rather than
    /// a waveform. -45 dB spreads speech across the middle of the grid, where
    /// the shape is actually legible.
    private static func displayLevel(_ value: Float) -> CGFloat {
        let floorDb: Double = -45
        guard value > 0.0001 else { return 0 }
        let db = 20 * log10(Double(value))
        return CGFloat(max(0, min(1, (db - floorDb) / -floorDb)))
    }

    private var elapsed: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .trailing)
    }

    private var label: String {
        switch model.state {
        case .copied:    return "Copied"
        case .recording: return Self.format(recorder.recordingDuration)
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}


/// Where each column of the matrix sits on screen.
///
/// Extracted from the view so the smooth-scroll maths can be tested without a
/// display. Positions advance *continuously* with the clock rather than jumping
/// once per audio callback — the tap delivers buffers at only ~10 Hz, which is
/// what made the indicator look clunky regardless of how often the view redrew.
enum DotMatrixGeometry {
    /// How much history is on screen at once: long enough to read, short enough
    /// to still feel live.
    static let windowSeconds: TimeInterval = 1.4

    /// The columns currently within the window, oldest first, with their x
    /// offsets and how long ago each one happened.
    ///
    /// Columns are positioned by *age* rather than by array index, which is what
    /// makes the motion continuous: two `now` values a single frame apart produce
    /// positions a single frame's worth of pixels apart, with no quantisation to
    /// bin boundaries.
    static func visibleColumns(
        binCount: Int,
        newest: TimeInterval,
        interval: TimeInterval,
        now: TimeInterval,
        width: CGFloat
    ) -> [(index: Int, x: CGFloat, age: TimeInterval)] {
        guard binCount > 0, interval > 0, width > 0, newest > 0 else { return [] }

        let pixelsPerSecond = width / CGFloat(windowSeconds)
        let pitch = CGFloat(interval) * pixelsPerSecond
        var result: [(index: Int, x: CGFloat, age: TimeInterval)] = []
        result.reserveCapacity(binCount)

        for index in 0..<binCount {
            // Reconstruct each bin's timestamp from the newest one, newest last.
            let binTime = newest - Double(binCount - 1 - index) * interval
            let age = now - binTime
            // A negative age means this bin's moment has not arrived yet, so it
            // is withheld until it does. That is what turns a burst of bins
            // delivered in a single audio callback into a continuous flow.
            guard age >= 0, age <= windowSeconds else { continue }
            let x = width - CGFloat(age) * pixelsPerSecond - pitch
            guard x > -pitch else { continue }
            result.append((index, x, age))
        }
        return result
    }
}

/// Thin wrapper so SwiftUI can use a real `NSVisualEffectView`.
///
/// `state = .active` matters here: DubScribe is usually *not* the frontmost app
/// while recording, and an inactive visual-effect view would render washed out.
/// This is also what gives the panel automatic light/dark and reduced-transparency
/// handling, so it looks native in either appearance.
struct HUDVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var alpha: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = alpha
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.alphaValue = alpha
    }
}
