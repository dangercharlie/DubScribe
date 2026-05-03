import Foundation
import Carbon
import AppKit

// MARK: - File-scope C callback (required — cannot be a closure with captures)
private func carbonHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let kind = GetEventKind(event)
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    DispatchQueue.main.async {
        switch hotKeyID.id {
        case HotkeyManager.holdID:
            if kind == UInt32(kEventHotKeyPressed)  { manager.onHoldKeyDown?() }
            if kind == UInt32(kEventHotKeyReleased) { manager.onHoldKeyUp?()   }
        case HotkeyManager.pushID:
            if kind == UInt32(kEventHotKeyPressed)  { manager.onPushKeyDown?() }
        default: break
        }
    }
    return noErr
}

/// Registers global hotkeys using Carbon RegisterEventHotKey.
/// Carbon hotkeys do NOT require Accessibility permission —
/// they fire via the Application Event Target (not a low-level event tap).
@MainActor
final class HotkeyManager: ObservableObject {

    // Carbon does not need Accessibility — always report true so UI stays clear
    @Published var isAccessibilityGranted: Bool = true

    // Carbon hotkey IDs (must be stable across reconfigures)
    static let holdID: UInt32 = 1
    static let pushID: UInt32 = 2
    // 'dbsr' = DubScribe signature
    private static let sig: FourCharCode = 0x64627372

    // Callbacks
    var onHoldKeyDown: (() -> Void)?
    var onHoldKeyUp:   (() -> Void)?
    var onPushKeyDown: (() -> Void)?

    // Diagnostic
    @Published var hotkeysRegistered = false
    @Published var lastEventTime: Date?

    private var holdRef: EventHotKeyRef?
    private var pushRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var selfPtr: Unmanaged<HotkeyManager>?

    private var holdHotkey: Hotkey = .defaultHoldHotkey
    private var pushHotkey: Hotkey = .defaultPushHotkey

    init() { setUp() }

    // MARK: - Configuration

    func configure(holdHotkey: Hotkey, pushHotkey: Hotkey) {
        self.holdHotkey = holdHotkey
        self.pushHotkey = pushHotkey
        tearDown()
        setUp()
    }

    /// Legacy compat
    func configure(hotkey: Hotkey) {
        configure(holdHotkey: hotkey, pushHotkey: pushHotkey)
    }

    /// No-op — Carbon doesn't need Accessibility
    func checkAccessibilityAndSetUp() { isAccessibilityGranted = true }
    func requestAccessibilityIfNeeded() { isAccessibilityGranted = true }

    // MARK: - Setup / Teardown

    private func setUp() {
        // Install event handler once
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let ptr = Unmanaged.passRetained(self)
        selfPtr = ptr
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            types.count,
            &types,
            ptr.toOpaque(),
            &handlerRef
        )
        if status != noErr {
            print("[DubScribe.Hotkey] InstallApplicationEventHandler failed: \(status)")
            ptr.release()
            selfPtr = nil
            return
        }

        registerHotkeys()
    }

    private func registerHotkeys() {
        // Hold hotkey
        var holdID_ = EventHotKeyID(signature: Self.sig, id: Self.holdID)
        let s1 = RegisterEventHotKey(
            holdHotkey.keyCode, holdHotkey.modifiers,
            holdID_, GetApplicationEventTarget(), 0, &holdRef
        )
        // Push hotkey
        var pushID_ = EventHotKeyID(signature: Self.sig, id: Self.pushID)
        let s2 = RegisterEventHotKey(
            pushHotkey.keyCode, pushHotkey.modifiers,
            pushID_, GetApplicationEventTarget(), 0, &pushRef
        )

        hotkeysRegistered = (s1 == noErr && s2 == noErr)
        print("[DubScribe.Hotkey] Hold=\(holdHotkey.displayString) registered=\(s1==noErr)  Push=\(pushHotkey.displayString) registered=\(s2==noErr)")
    }

    nonisolated private func cleanUp(hold: EventHotKeyRef?, push: EventHotKeyRef?, handler: EventHandlerRef?, ptr: Unmanaged<HotkeyManager>?) {
        if let r = hold { UnregisterEventHotKey(r) }
        if let r = push { UnregisterEventHotKey(r) }
        if let r = handler { RemoveEventHandler(r) }
        ptr?.release()
    }

    private func tearDown() {
        cleanUp(hold: holdRef, push: pushRef, handler: handlerRef, ptr: selfPtr)
        holdRef = nil
        pushRef = nil
        handlerRef = nil
        selfPtr = nil
        hotkeysRegistered = false
    }

    deinit { 
        cleanUp(hold: holdRef, push: pushRef, handler: handlerRef, ptr: selfPtr)
    }
}
