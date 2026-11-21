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

    /// One double-Shift step over the typed buffer.
    struct Step: Equatable {
        enum Kind { case word, extend, toggle }
        /// Keys to re-type in this step.
        let convert: Range<Int>
        /// The whole converted span after this step (what the next press extends).
        let span: Range<Int>
        /// `.word` and `.toggle` move to the next layout; `.extend` keeps the span's current layout.
        let kind: Kind
    }

    /// Decides what a double Shift converts. `previous` is the span converted by the
    /// previous press, if nothing was typed since: then the word before it is added to it.
    /// With no word left before the span, the whole span is toggled to the next layout.
    static func nextStep(in buffer: [TypedKey], extending previous: Range<Int>?) -> Step? {
        guard let span = previous, span.upperBound <= buffer.count, !span.isEmpty else {
            guard let word = lastWord(in: buffer) else { return nil }
            return Step(convert: word, span: word, kind: .word)
        }
        if let word = lastWord(in: Array(buffer[..<span.lowerBound])) {
            return Step(convert: word, span: word.lowerBound..<span.upperBound, kind: .extend)
        }
        return Step(convert: span, span: span, kind: .toggle)
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

/// Remembers the span the last double Shift converted, valid while the buffer stays
/// exactly as that conversion left it (any typing, click, arrow or app switch changes it).
struct PhraseTracker {
    private var span: Range<Int>?
    private var snapshot: [String] = []

    /// The span to extend, or nil if the buffer changed since the last conversion.
    func previous(for buffer: [TypedKey]) -> Range<Int>? {
        guard let span, buffer.map(\.produced) == snapshot else { return nil }
        return span
    }

    mutating func record(_ span: Range<Int>, buffer: [TypedKey]) {
        self.span = span
        snapshot = buffer.map(\.produced)
    }

    mutating func reset() { span = nil; snapshot = [] }
}
