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

// Typing run: double Shift converts everything typed since the last reset, simulated
// like AppDelegate.convert() does it.
func press(_ buffer: inout [TypedKey], _ ids: inout [String], _ run: inout TypingRun, _ screen: inout String) {
    guard let range = run.range(in: buffer) else { return }
    let target = Layouts.next(after: ids[range.upperBound - 1], in: [abc, ru])!
    let newText = Converter.retype(buffer[range], in: target)
    screen.removeLast(buffer[range].reduce(0) { $0 + $1.produced.count })
    screen += newText.joined()
    for (i, s) in zip(range, newText) { buffer[i].produced = s; ids[i] = target.id }
    run.didConvert()
}
func type(_ text: String, in layout: KeyboardLayout, _ buffer: inout [TypedKey], _ ids: inout [String],
          _ run: inout TypingRun, _ screen: inout String) {
    for k in keys(text, in: layout) { run.willType(at: buffer.count); buffer.append(k); ids.append(layout.id) }
    screen += text
}
do {
    var buffer: [TypedKey] = [], ids: [String] = [], run = TypingRun(), screen = ""
    type("ghbdtn vbh rfr ltkf", in: abc, &buffer, &ids, &run, &screen)
    press(&buffer, &ids, &run, &screen); check(screen, "привет мир как дела", "run: whole phrase at once")
    check(buffer.map(\.produced).joined(), screen, "run: buffer matches screen")
    press(&buffer, &ids, &run, &screen); check(screen, "ghbdtn vbh rfr ltkf", "run: second press toggles back")
    press(&buffer, &ids, &run, &screen); check(screen, "привет мир как дела", "run: third press toggles again")

    // Typing after a conversion starts a new run: only the new text is converted
    type(" тест", in: ru, &buffer, &ids, &run, &screen)
    press(&buffer, &ids, &run, &screen); check(screen, "привет мир как дела ntcn", "run: only text typed after the conversion")
}
do {
    // Only spaces or nothing: no run (falls back to the selection)
    var buffer = keys("   ", in: abc)
    check(TypingRun().range(in: buffer) == nil ? "nil" : "range", "nil", "run: spaces only")
    buffer = []
    check(TypingRun().range(in: buffer) == nil ? "nil" : "range", "nil", "run: empty")
    // Backspace past the run start and dropping old keys keep the start valid
    var r = TypingRun()
    r.didConvert(); r.willType(at: 5)
    r.didShrink(to: 3); check("\(r.start)", "3", "run: shrink clamps start")
    r.didDropFirst(10); check("\(r.start)", "0", "run: drop clamps start")
}

// Case inversion
check(CaseInverter.invert("пРИВЕТ"), "Привет", "case: ru")
check(CaseInverter.invert("Hello World 123!"), "hELLO wORLD 123!", "case: en, digits and punctuation kept")
check(CaseInverter.invert("straße"), "STRAßE", "case: ß kept (would become SS)")
check(CaseInverter.hasCase("123 ,.") ? "yes" : "no", "no", "case: nothing to flip")
do {
    let typed = keys("Ghbdtn vbh", in: abc)
    let inverted = CaseInverter.invert(typed[...])
    check(inverted.map(\.produced).joined(), "gHBDTN VBH", "case keys: produced")
    check(Converter.retype(inverted[...], in: abc).joined(), "gHBDTN VBH", "case keys: strokes type the new case")
    check(Converter.retype(inverted[...], in: ru).joined(), "пРИВЕТ МИР", "case keys: then layout conversion keeps case")
    check(CaseInverter.invert(inverted[...]).map(\.produced).joined(), "Ghbdtn vbh", "case keys: second press reverts")

    // Caps Lock on: "G" typed without Shift. Inversion drops Caps Lock from the stroke.
    let g = abc.reverseMap["g"]!
    let caps = [TypedKey(stroke: KeyStroke(keyCode: g.keyCode, shift: false, option: false, capsLock: true), produced: "G")]
    check(Converter.retype(caps[...], in: ru).joined(), "П", "caps: layout conversion before inversion")
    let capsInv = CaseInverter.invert(caps[...])
    check(capsInv[0].produced, "g", "caps: inverted produced")
    check(capsInv[0].stroke.capsLock ? "on" : "off", "off", "caps: stroke drops Caps Lock")
    check(Converter.retype(capsInv[...], in: ru).joined(), "п", "caps: layout conversion after inversion")
}
do {
    // Case toggle then layout conversion on the same run, as AppDelegate does it.
    var buffer: [TypedKey] = [], ids: [String] = [], run = TypingRun(), screen = ""
    type("Ghbdtn", in: abc, &buffer, &ids, &run, &screen)
    let range = run.range(in: buffer)!
    let inv = CaseInverter.invert(buffer[range])
    screen.removeLast(buffer[range].reduce(0) { $0 + $1.produced.count })
    screen += inv.map(\.produced).joined()
    buffer.replaceSubrange(range, with: inv)
    run.didConvert()
    check(screen, "gHBDTN", "case run: toggled")
    press(&buffer, &ids, &run, &screen); check(screen, "пРИВЕТ", "case run: then double Shift converts it")
}

// Per-app exclusions
func yes(_ b: Bool) -> String { b ? "yes" : "no" }
var ex = ExclusionList()
check(yes(ex.isExcluded("com.apple.Terminal")), "yes", "default terminal")
check(yes(ex.isExcluded("com.jetbrains.intellij")), "yes", "jetbrains prefix")
check(yes(ex.isExcluded("com.jetbrainsfoo")), "no", "prefix needs the dot")
check(yes(ex.isExcluded("com.apple.Safari")), "no", "safari not excluded")
check(yes(ex.isExcluded(nil)), "no", "nil bundle id")
ex.toggle("com.apple.Safari")
check(yes(ex.isExcluded("com.apple.Safari")), "yes", "toggle on")
ex.toggle("com.apple.Safari")
check(yes(ex.isExcluded("com.apple.Safari")), "no", "toggle off")
ex.toggle("com.jetbrains.pycharm")
check(yes(ex.isExcluded("com.jetbrains.intellij")), "no", "toggle off removes prefix entry")
ex.remove("com.apple.Terminal")
check(yes(ex.isExcluded("com.apple.Terminal")), "no", "remove")
check(yes(ExclusionList([]).isExcluded("com.apple.Terminal")), "no", "empty list")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
