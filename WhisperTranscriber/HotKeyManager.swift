import Carbon
import SwiftUI

typealias HotKeyHandler = () -> Void

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: HotKeyHandler?
    private var releaseHandler: HotKeyHandler?
    private var eventHandlerInstalled = false

    private init() {
        // Private initializer for singleton
    }

    /// Shift alone isn't enough: ⇧S or a bare Space would take that key from every app.
    static func hasRequiredModifier(_ chord: String) -> Bool {
        ["⌃", "⌥", "⌘"].contains { chord.contains($0) }
    }

    @discardableResult
    func register(chord: String, handler: @escaping HotKeyHandler, onRelease: HotKeyHandler? = nil) -> Bool {
        // 1) Figure out modifiers
        let modMap: [(String, UInt32)] = [
            ("⌥", UInt32(optionKey)),
            ("⌃", UInt32(controlKey)),
            ("⇧", UInt32(shiftKey)),
            ("⌘", UInt32(cmdKey))
        ]
        let modifiers = modMap.reduce(0) { acc, pair in
            chord.contains(pair.0) ? acc | pair.1 : acc
        }

        // 2) Pick the key: "Space", or the *last* letter or digit in the string
        let keyCode: UInt32?
        if chord.hasSuffix("Space") {
            keyCode = UInt32(kVK_Space)
        } else {
            keyCode = chord.last(where: { $0.isLetter || $0.isNumber }).flatMap(virtualKeyCode(for:))
        }
        guard let vk = keyCode else {
            Log.hotkey.error("❌ couldn't parse hotkey: \(chord))")
            return false
        }
        guard HotKeyManager.hasRequiredModifier(chord) else {
            Log.hotkey.error("❌ hotkey needs ⌃, ⌥ or ⌘: \(chord)")
            return false
        }

        // 3) Unregister old, register new
        unregister()

        let hotKeyID = EventHotKeyID(signature: UTGetOSTypeFromString("SwHK"), id: 1)

        installEventHandlerIfNeeded()

        let status = RegisterEventHotKey(vk, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)

        if status == noErr {
            self.hotKeyHandler = handler
            self.releaseHandler = onRelease
            Log.hotkey.info("✅ Registered \(chord)) → keyCode: \(vk)) mods: \(modifiers))")
            return true
        } else {
            Log.hotkey.error("❌ failed to register hotkey: \(chord))")
            return false
        }
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// One handler serves every registration, routing presses and releases to the current handlers.
    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(GetEventDispatcherTarget(), {
            (nextHandler, event, userData) -> OSStatus in
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                HotKeyManager.shared.releaseHandler?()
            } else {
                HotKeyManager.shared.hotKeyHandler?()
            }
            return noErr
        }, eventTypes.count, &eventTypes, nil, nil)

        eventHandlerInstalled = status == noErr
    }

    private func virtualKeyCode(for char: Character) -> UInt32? {
        let keyMap: [Character: UInt32] = [
            "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
            "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
            "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
            "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
            "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
            "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
            "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
            "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
            "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z), "0": UInt32(kVK_ANSI_0),
            "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
            "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6),
            "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9)
        ]
        return keyMap[char.uppercased().first ?? Character("")]
    }
}
