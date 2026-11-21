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

    /// What the same keys would have typed in another layout.
    static func retype(_ keys: ArraySlice<TypedKey>, in layout: KeyboardLayout) -> [String] {
        keys.map { layout.character(for: $0.stroke) ?? $0.produced }
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
