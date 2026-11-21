import Cocoa

/// Synthetic keyboard input. Every event is tagged so our own key monitor ignores it.
enum TextOutput {
    static let marker: Int64 = 0x5241_534B // "RASK"
    private static let source = CGEventSource(stateID: .privateState)

    private static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
        usleep(1500)
    }

    static func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            post(e)
        }
    }

    static func backspace(_ count: Int) {
        for _ in 0..<max(0, count) { key(51) }
    }

    /// Types text character by character, independent of the active layout.
    static func type(_ text: String) {
        for ch in text {
            let units = Array(String(ch).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                post(e)
            }
        }
    }

    static func copy() { key(8, flags: .maskCommand) } // ⌘C
}
