import Carbon
import Foundation

/// One physical key press: which key and which modifiers changed the character.
struct KeyStroke: Equatable {
    let keyCode: UInt16
    let shift: Bool
    let option: Bool
    let capsLock: Bool
}

/// A keyboard layout enabled in System Settings (ABC, Russian, ...).
final class KeyboardLayout {
    let source: TISInputSource
    let id: String
    let name: String
    private let layoutData: CFData

    init?(source: TISInputSource) {
        guard let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        self.source = source
        self.layoutData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        self.id = KeyboardLayout.stringProperty(source, kTISPropertyInputSourceID) ?? "?"
        self.name = KeyboardLayout.stringProperty(source, kTISPropertyLocalizedName) ?? id
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The character this layout produces for a key stroke, or nil for non-printing keys.
    func character(for stroke: KeyStroke) -> String? {
        var modifiers: UInt32 = 0
        if stroke.shift { modifiers |= UInt32(shiftKey) }
        if stroke.option { modifiers |= UInt32(optionKey) }
        if stroke.capsLock { modifiers |= UInt32(alphaLock) }
        let modifierState = (modifiers >> 8) & 0xFF

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = CFDataGetBytePtr(layoutData).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(layout, stroke.keyCode, UInt16(kUCKeyActionDown), modifierState,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let result = String(utf16CodeUnits: chars, count: length)
        if result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
        return result
    }

    /// Character -> key stroke that types it in this layout (plain keys win over Shift, Shift over Option).
    lazy var reverseMap: [Character: KeyStroke] = {
        var map: [Character: KeyStroke] = [:]
        for (shift, option) in [(false, false), (true, false), (false, true), (true, true)] {
            for code in UInt16(0)..<UInt16(128) {
                let stroke = KeyStroke(keyCode: code, shift: shift, option: option, capsLock: false)
                guard let s = character(for: stroke), s.count == 1, let ch = s.first else { continue }
                if map[ch] == nil { map[ch] = stroke }
            }
        }
        return map
    }()
}

enum Layouts {
    /// Keyboard layouts the user can switch to, in System Settings order.
    static func enabled() -> [KeyboardLayout] {
        let filter = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
        return list.compactMap(KeyboardLayout.init(source:))
    }

    static func currentID() -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The layout after `id` in the enabled list, wrapping around.
    static func next(after id: String?, in layouts: [KeyboardLayout]) -> KeyboardLayout? {
        guard !layouts.isEmpty else { return nil }
        guard let id, let i = layouts.firstIndex(where: { $0.id == id }) else { return layouts.count > 1 ? layouts[1] : layouts[0] }
        return layouts[(i + 1) % layouts.count]
    }

    static func select(_ layout: KeyboardLayout) {
        TISSelectInputSource(layout.source)
    }
}
