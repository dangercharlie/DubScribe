import Foundation
import Carbon
import AppKit

/// Manages two independent global hotkeys via a single CGEventTap:
///   - Hold hotkey: fires onHoldKeyDown / onHoldKeyUp (press-and-hold recording)
///   - Push hotkey: fires onPushKeyDown (toggle recording on each press)
@MainActor
final class HotkeyManager: ObservableObject {

    @Published var isAccessibilityGranted: Bool = false

    // Hold-to-record callbacks
    var onHoldKeyDown: (() -> Void)?
    var onHoldKeyUp: (() -> Void)?

    // Push-to-record callback (toggle on each unique key-down)
    var onPushKeyDown: (() -> Void)?

    // Legacy single-hotkey callbacks — preserved for compatibility
    var onKeyDown: (() -> Void)? {
        get { onHoldKeyDown }
        set { onHoldKeyDown = newValue }
    }
    var onKeyUp: (() -> Void)? {
        get { onHoldKeyUp }
        set { onHoldKeyUp = newValue }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var holdHotkey: Hotkey = .defaultHoldHotkey
    private var pushHotkey: Hotkey = .defaultPushHotkey

    private var isHoldKeyDown = false
    private var isPushKeyDown = false

    // MARK: - Configuration

    func configure(holdHotkey: Hotkey, pushHotkey: Hotkey) {
        self.holdHotkey = holdHotkey
        self.pushHotkey = pushHotkey
        restart()
    }

    /// Legacy single-hotkey configure (maps to holdHotkey)
    func configure(hotkey: Hotkey) {
        configure(holdHotkey: hotkey, pushHotkey: pushHotkey)
    }

    private func restart() {
        tearDown()
        checkAccessibilityAndSetUp()
    }

    func checkAccessibilityAndSetUp() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String as CFString
        let options = [key: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = trusted
        if trusted { setUp() }
    }

    func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String as CFString
        let options = [key: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkAccessibilityAndSetUp()
        }
    }

    // MARK: - CGEventTap

    private func setUp() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return mgr.handleEvent(type: type, event: event)
            },
            userInfo: selfPtr.toOpaque()
        ) else {
            selfPtr.release()
            print("HotkeyManager: CGEventTap creation failed — check Accessibility permission.")
            return
        }

        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func tearDown() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isHoldKeyDown = false
        isPushKeyDown = false
    }

    // MARK: - Event Handling

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let activeMods = extractMods(from: flags)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        let matchesHold = keyCode == holdHotkey.keyCode && activeMods == holdHotkey.modifiers
        let matchesPush = keyCode == pushHotkey.keyCode && activeMods == pushHotkey.modifiers

        guard matchesHold || matchesPush else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            if matchesHold && !isAutoRepeat && !isHoldKeyDown {
                isHoldKeyDown = true
                DispatchQueue.main.async { [weak self] in self?.onHoldKeyDown?() }
            }
            if matchesPush && !isAutoRepeat && !isPushKeyDown {
                isPushKeyDown = true
                DispatchQueue.main.async { [weak self] in self?.onPushKeyDown?() }
            }
        } else if type == .keyUp {
            if matchesHold {
                isHoldKeyDown = false
                DispatchQueue.main.async { [weak self] in self?.onHoldKeyUp?() }
            }
            if matchesPush {
                isPushKeyDown = false
            }
        }

        return nil // consume matched events
    }

    private func extractMods(from flags: CGEventFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.maskControl)  { mods |= UInt32(controlKey) }
        if flags.contains(.maskAlternate){ mods |= UInt32(optionKey)  }
        if flags.contains(.maskShift)    { mods |= UInt32(shiftKey)   }
        if flags.contains(.maskCommand)  { mods |= UInt32(cmdKey)     }
        return mods
    }

    deinit {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }
}
