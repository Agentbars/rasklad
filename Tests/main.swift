import Foundation

// Checks conversion against the layouts enabled on this Mac (expects ABC + Russian).
var failures = 0
func check(_ got: String, _ expected: String, _ label: String) {
    if got == expected { print("ok   \(label): \(got)") } else { print("FAIL \(label): got \(got), want \(expected)"); failures += 1 }
}

let layouts = Layouts.enabled()
print("layouts:", layouts.map { "\($0.name) (\($0.id))" })
guard let abc = layouts.first(where: { $0.id.hasSuffix(".ABC") || $0.id.hasSuffix(".US") }),
      let ru = layouts.first(where: { $0.id.hasSuffix(".Russian") }) else {
    print("need ABC/US and Russian layouts enabled"); exit(1)
}

// Typed keys -> other layout
func keys(_ text: String, in layout: KeyboardLayout) -> [TypedKey] {
    text.map { TypedKey(stroke: layout.reverseMap[$0]!, produced: String($0)) }
}
check(Converter.retype(keys("ghbdtn", in: abc)[...], in: ru).joined(), "привет", "keys en->ru")
check(Converter.retype(keys("Ghbdtn", in: abc)[...], in: ru).joined(), "Привет", "keys shift")
check(Converter.retype(keys("руддщ", in: ru)[...], in: abc).joined(), "hello", "keys ru->en")
check(Converter.retype(keys("ntcn.", in: abc)[...], in: ru).joined(), "тестю", "keys punctuation")

// Last word detection
let buf = keys("ghbdtn vbh  ", in: abc)
if let r = Converter.lastWord(in: buf) { check(String(buf[r].map(\.produced).joined()), "vbh", "last word") } else { check("nil", "vbh", "last word") }
check(Converter.lastWord(in: keys("   ", in: abc)) == nil ? "nil" : "range", "nil", "only spaces")

// Selected text
check(Converter.convertText("ghbdtn vbh", layouts: [abc, ru])?.text ?? "nil", "привет мир", "text en->ru")
check(Converter.convertText("Руддщ цщкдв!", layouts: [abc, ru])?.text ?? "nil", "Hello world!", "text ru->en")
check(Converter.convertText("123", layouts: [abc, ru])?.text ?? "nil", "nil", "no letters")

// Phrase extension: repeated double Shift, simulated like AppDelegate.convert() does it
func press(_ buffer: inout [TypedKey], _ layoutIDs: inout [String], _ tracker: inout PhraseTracker,
           _ screen: inout String) {
    guard let step = Converter.nextStep(in: buffer, extending: tracker.previous(for: buffer)) else { return }
    let spanLayout = layoutIDs[step.span.upperBound - 1]
    let target = step.kind == .extend ? layouts.first { $0.id == spanLayout }!
                                      : Layouts.next(after: spanLayout, in: [abc, ru])!
    let newWord = Converter.retype(buffer[step.convert], in: target)
    let toDelete = buffer[step.convert.lowerBound...].reduce(0) { $0 + $1.produced.count }
    screen.removeLast(toDelete)
    screen += newWord.joined() + buffer[step.convert.upperBound...].map(\.produced).joined()
    for (i, s) in zip(step.convert, newWord) { buffer[i].produced = s; layoutIDs[i] = target.id }
    tracker.record(step.span, buffer: buffer)
}
do {
    var buffer = keys("ghbdtn  vbh ", in: abc)
    var ids = Array(repeating: abc.id, count: buffer.count)
    var tracker = PhraseTracker()
    var screen = "ghbdtn  vbh "
    press(&buffer, &ids, &tracker, &screen); check(screen, "ghbdtn  мир ", "phrase 1st press")
    press(&buffer, &ids, &tracker, &screen); check(screen, "привет  мир ", "phrase 2nd press extends")
    check(buffer.map(\.produced).joined(), screen, "phrase buffer matches screen")
    press(&buffer, &ids, &tracker, &screen); check(screen, "ghbdtn  vbh ", "phrase 3rd press toggles back")
    press(&buffer, &ids, &tracker, &screen); check(screen, "привет  мир ", "phrase 4th press toggles again")

    // Typing in between starts over from the last word
    buffer += keys("ntcn", in: abc); ids += Array(repeating: abc.id, count: 4); screen += "ntcn"
    press(&buffer, &ids, &tracker, &screen); check(screen, "привет  мир тест", "phrase reset by typing")

    // One word only: second press toggles it back, like before
    var b2 = keys("ghbdtn", in: abc), ids2 = Array(repeating: abc.id, count: 6)
    var t2 = PhraseTracker(), s2 = "ghbdtn"
    press(&b2, &ids2, &t2, &s2); check(s2, "привет", "single word 1st")
    press(&b2, &ids2, &t2, &s2); check(s2, "ghbdtn", "single word toggles back")
}
check(Converter.nextStep(in: keys("ab cd", in: abc), extending: 3..<5)?.kind == .extend ? "extend" : "other",
      "extend", "step kind extend")
check(Converter.nextStep(in: keys("  cd", in: abc), extending: 2..<4)?.kind == .toggle ? "toggle" : "other",
      "toggle", "step kind toggle at buffer start")
check(Converter.nextStep(in: keys("ab", in: abc), extending: 0..<9)?.span == 0..<2 ? "word" : "other",
      "word", "stale span falls back to last word")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
