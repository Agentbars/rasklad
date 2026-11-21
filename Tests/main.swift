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
