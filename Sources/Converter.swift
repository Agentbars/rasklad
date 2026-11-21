import Foundation

/// A key the user typed and the text it put on screen.
struct TypedKey {
    let stroke: KeyStroke
    var produced: String
}

enum Converter {
    static func isSpace(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isWhitespace }
    }

    /// Range of the last word in the buffer; spaces typed after it are not part of the range.
    static func lastWord(in buffer: [TypedKey]) -> Range<Int>? {
        var end = buffer.count
        while end > 0, isSpace(buffer[end - 1].produced) { end -= 1 }
        guard end > 0 else { return nil }
        var start = end
        while start > 0, !isSpace(buffer[start - 1].produced) { start -= 1 }
        return start..<end
    }

    /// What the same keys would have typed in another layout. Spaces are kept as typed.
    static func retype(_ keys: ArraySlice<TypedKey>, in layout: KeyboardLayout) -> [String] {
        keys.map { isSpace($0.produced) ? $0.produced : (layout.character(for: $0.stroke) ?? $0.produced) }
    }

    /// Converts ready-made text (a selection): guesses the layout it was typed in
    /// by its letters and re-types it in the next layout.
    static func convertText(_ text: String, layouts: [KeyboardLayout]) -> (text: String, target: KeyboardLayout)? {
        guard layouts.count >= 2 else { return nil }
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return nil }

        var best: (layout: KeyboardLayout, score: Int)?
        for layout in layouts {
            let score = letters.reduce(0) { $0 + (layout.reverseMap[$1] != nil ? 1 : 0) }
            if score > (best?.score ?? 0) { best = (layout, score) }
        }
        guard let source = best?.layout,
              let target = Layouts.next(after: source.id, in: layouts) else { return nil }

        var out = ""
        for ch in text {
            if let stroke = source.reverseMap[ch], let typed = target.character(for: stroke) {
                out += typed
            } else {
                out.append(ch)
            }
        }
        return (out, target)
    }
}

/// The part of the typed buffer a double Shift converts: everything typed since the
/// buffer was last cleared (Return, click, arrows, shortcut, app switch, manual layout
/// switch) or since the last conversion, once typing continues after it.
/// Pressing the hotkey again right after a conversion converts the same text back.
struct TypingRun {
    private(set) var start = 0
    private var afterConversion = false

    mutating func reset() {
        start = 0
        afterConversion = false
    }

    /// Call before a typed key is appended at `index`.
    mutating func willType(at index: Int) {
        if afterConversion {
            start = index
            afterConversion = false
        }
    }

    /// Call after keys were removed from the end (backspace); `count` is the new buffer size.
    mutating func didShrink(to count: Int) { start = min(start, count) }

    /// Call after `n` keys were dropped from the front of the buffer.
    mutating func didDropFirst(_ n: Int) { start = max(0, start - n) }

    mutating func didConvert() { afterConversion = true }

    /// Range to convert, or nil when the run holds no text (only spaces or nothing).
    func range(in buffer: [TypedKey]) -> Range<Int>? {
        let from = min(start, buffer.count)
        guard buffer[from...].contains(where: { !$0.produced.isEmpty && !Converter.isSpace($0.produced) }) else { return nil }
        return from..<buffer.count
    }
}

/// Case inversion («пРИВЕТ» → «Привет», «hello» → «HELLO»). Pure logic.
enum CaseInverter {
    /// The character with its case flipped, or nil when it has no case or the flip
    /// would change its length (ß → SS).
    static func invert(_ ch: Character) -> Character? {
        let flipped: String
        if ch.isUppercase { flipped = ch.lowercased() } else if ch.isLowercase { flipped = ch.uppercased() } else { return nil }
        guard flipped.count == 1, let result = flipped.first, result != ch else { return nil }
        return result
    }

    static func invert(_ text: String) -> String {
        String(text.map { invert($0) ?? $0 })
    }

    /// Typed keys with inverted case. A letter key's stroke is rewritten so that it types the
    /// new case on its own: Shift on for upper case, off for lower, Caps Lock dropped.
    /// Then converting the layout afterwards keeps the new case.
    static func invert(_ keys: ArraySlice<TypedKey>) -> [TypedKey] {
        keys.map { key in
            let produced = invert(key.produced)
            guard produced != key.produced else { return key }
            let upper = produced.contains { $0.isUppercase }
            let s = key.stroke
            return TypedKey(stroke: KeyStroke(keyCode: s.keyCode, shift: upper, option: s.option, capsLock: false),
                            produced: produced)
        }
    }

    /// True when the text has at least one letter whose case can be flipped.
    static func hasCase(_ text: String) -> Bool { text.contains { invert($0) != nil } }
}
