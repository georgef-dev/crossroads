// The global shortcut that opens the panel.
//
// Carbon's RegisterEventHotKey is the only way to take a system-wide shortcut
// without asking for Accessibility permission, and it refuses a combination
// another app already holds. That refusal is what makes
// Settings.ShortcutNeverConflicts hold: register the new one first, and keep
// the old one when the new one will not take.

import AppKit
import Carbon.HIToolbox

import CrossroadsCore

@MainActor
final class Hotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var fire: () -> Void = {}

    /// Our own id, so the handler knows the press is ours.
    private static let identifier: UInt32 = 0x4352_4F53  // "CROS"

    init() {}

    // Isolated, because the Carbon handles it gives back are not Sendable.
    isolated deinit {
        if let handler { RemoveEventHandler(handler) }
        if let reference { UnregisterEventHotKey(reference) }
    }

    /// Takes `shortcut` system-wide, keeping the current one when the new one
    /// will not register. Returns whether the new shortcut is now in effect.
    @discardableResult
    func register(_ shortcut: Shortcut, onPress: @escaping () -> Void) -> Bool {
        guard let code = keyCode(for: shortcut.key) else { return false }

        installHandlerIfNeeded()

        let identifier = EventHotKeyID(signature: Self.identifier, id: 1)
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            code,
            carbonModifiers(shortcut),
            identifier,
            GetEventDispatcherTarget(),
            0,
            &newReference
        )

        // The combination is taken, so the old shortcut stays as it was.
        guard status == noErr, let newReference else { return false }

        // Only once the new one is registered does the old one go, so there is
        // never a moment with no shortcut and never a moment with two.
        if let reference { UnregisterEventHotKey(reference) }
        self.reference = newReference
        self.fire = onPress
        return true
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var kind = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(context).takeUnretainedValue()
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                guard pressed.signature == Hotkey.identifier else {
                    return OSStatus(eventNotHandledErr)
                }
                MainActor.assumeIsolated { hotkey.fire() }
                return noErr
            },
            1,
            &kind,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    private func carbonModifiers(_ shortcut: Shortcut) -> UInt32 {
        var modifiers: Int = 0
        if shortcut.command { modifiers |= cmdKey }
        if shortcut.option { modifiers |= optionKey }
        if shortcut.control { modifiers |= controlKey }
        if shortcut.shift { modifiers |= shiftKey }
        return UInt32(modifiers)
    }
}

/// The virtual key code for a shortcut's key, or nothing when the system has
/// no code for it. Virtual codes follow the physical keyboard, not the layout,
/// so these are the ANSI positions.
private func keyCode(for key: String) -> UInt32? {
    if let code = keyCodes[key] { return UInt32(code) }
    return nil
}

private let keyCodes: [String: Int] = [
    "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
    "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
    "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
    "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
    "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
    "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
    "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
    "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
    "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4,
    "F5": kVK_F5, "F6": kVK_F6, "F7": kVK_F7, "F8": kVK_F8,
    "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
    "SPACE": kVK_Space,
]
