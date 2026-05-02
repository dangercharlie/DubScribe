import Foundation
import Carbon
import AppKit

/// Registers a global hotkey using CGEventTap (requires Accessibility permission).
/// Detects keyDown and keyUp events for true press-and-hold behaviour.
@MainActor
final class HotkeyManager: ObservableObject {

    @Published var isAccessibilityGranted: Bool = false

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentHotkey: Hotkey = .defaultHotkey
    private var isKeyCurrentlyDown = false

    // MARK: - Setup

    func configure(hotkey: Hotkey) {
        currentHotkey = hotkey
        restart()
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
        if trusted {
            setUp()
        }
    }

    func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String as CFString
        let options = [key: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        // Poll after a short delay to update state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkAccessibilityAndSetUp()
        }
    }

    // MARK: - CGEventTap

    private func setUp() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // We need an unmanaged self pointer for the callback
        let selfPtr = Unmanaged.passRetained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr.toOpaque()
        ) else {
            selfPtr.release()
            print("HotkeyManager: CGEvent tap could not be created. Check Accessibility permission.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func tearDown() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyCurrentlyDown = false
    }

    // MARK: - Event Handling

    // Called from the CGEvent tap callback (background thread).
    // We dispatch to main for all Swift state changes.
    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let targetKeyCode = currentHotkey.keyCode
        let targetMods = currentHotkey.modifiers

        guard keyCode == targetKeyCode else {
            return Unmanaged.passRetained(event)
        }

        let ctrlDown  = flags.contains(.maskControl)
        let optDown   = flags.contains(.maskAlternate)
        let shiftDown = flags.contains(.maskShift)
        let cmdDown   = flags.contains(.maskCommand)

        var activeMods: UInt32 = 0
        if ctrlDown  { activeMods |= UInt32(controlKey) }
        if optDown   { activeMods |= UInt32(optionKey)  }
        if shiftDown { activeMods |= UInt32(shiftKey)   }
        if cmdDown   { activeMods |= UInt32(cmdKey)     }

        guard activeMods == targetMods else {
            return Unmanaged.passRetained(event)
        }

        // Consume the event so it doesn't reach other apps
        if type == .keyDown {
            // autorepeat: keyDown fires repeatedly while key is held
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isAutoRepeat && !isKeyCurrentlyDown {
                isKeyCurrentlyDown = true
                DispatchQueue.main.async { [weak self] in
                    self?.onKeyDown?()
                }
            }
            return nil // consume
        } else if type == .keyUp {
            isKeyCurrentlyDown = false
            DispatchQueue.main.async { [weak self] in
                self?.onKeyUp?()
            }
            return nil // consume
        }

        return Unmanaged.passRetained(event)
    }

    deinit {
        // Disable the tap synchronously — CF types are safe to use from any thread
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
