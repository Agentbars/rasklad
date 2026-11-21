import Cocoa

// Pure tests for TapDetector (no permissions or layouts needed).
var failures = 0
func check(_ got: Bool, _ expected: Bool, _ label: String) {
    if got == expected { print("ok   \(label)") } else { print("FAIL \(label): got \(got), want \(expected)"); failures += 1 }
}

// Real keyboard events carry device bits; synthetic ones may carry only the generic mask.
let bits: [Int64: UInt64] = [59: 0x1, 56: 0x2, 60: 0x4, 55: 0x8, 54: 0x10, 58: 0x20, 61: 0x40, 62: 0x2000]
let masks: [Int64: CGEventFlags] = [56: .maskShift, 60: .maskShift, 58: .maskAlternate, 61: .maskAlternate,
                                    59: .maskControl, 62: .maskControl, 55: .maskCommand, 54: .maskCommand]

/// Events: (keyCode, down?, time). Returns how many times the detector fired.
func run(_ hotkey: Hotkey, _ events: [(Int64, Bool, TimeInterval)], deviceBits: Bool = true,
         cancelAt: TimeInterval? = nil) -> Int {
    var d = TapDetector()
    d.hotkey = hotkey
    var held = Set<Int64>()
    var fired = 0
    var cancelled = false
    for (code, down, t) in events {
        if let c = cancelAt, t > c, !cancelled { d.cancel(); cancelled = true }
        if down { held.insert(code) } else { held.remove(code) }
        var flags = CGEventFlags()
        for k in held {
            flags.formUnion(masks[k]!)
            if deviceBits { flags = CGEventFlags(rawValue: flags.rawValue | bits[k]!) }
        }
        if d.flagsChanged(keyCode: code, flags: flags, at: t) { fired += 1 }
    }
    return fired
}

func double(_ code: Int64, gap: TimeInterval = 0.2, hold: TimeInterval = 0.05) -> [(Int64, Bool, TimeInterval)] {
    [(code, true, 0), (code, false, hold), (code, true, hold + gap), (code, false, 2 * hold + gap)]
}

check(run(.doubleShift, double(56)) == 1, true, "double left Shift")
check(run(.doubleShift, double(60)) == 1, true, "double right Shift")
check(run(.doubleShift, double(56), deviceBits: false) == 1, true, "double Shift, synthetic flags")
check(run(.doubleShift, [(56, true, 0), (56, false, 0.05), (60, true, 0.2), (60, false, 0.25)]) == 1, true, "left then right Shift")
check(run(.doubleShift, double(58)) == 0, true, "Option ignored when Shift chosen")
check(run(.doubleOption, double(58)) == 1, true, "double left Option")
check(run(.doubleOption, double(61)) == 1, true, "double right Option")
check(run(.doubleControl, double(62)) == 1, true, "double right Control")
check(run(.doubleShift, double(56, gap: 0.5)) == 0, true, "second tap too late")
check(run(.doubleShift, double(56, hold: 0.35)) == 0, true, "taps too long")
check(run(.doubleShift, double(56), cancelAt: 0.1) == 0, true, "key press between taps")
check(run(.doubleShift, [(56, true, 0), (56, false, 0.05), (55, true, 0.1), (55, false, 0.15),
                         (56, true, 0.2), (56, false, 0.25)]) == 0, true, "Command between taps")
check(run(.doubleShift, [(55, true, 0), (56, true, 0.01), (56, false, 0.05), (56, true, 0.1), (56, false, 0.15),
                         (55, false, 0.2)]) == 0, true, "Shift with Command held")
check(run(.doubleShift, [(56, true, 0), (56, false, 0.05), (56, true, 0.1), (56, false, 0.15),
                         (56, true, 0.2), (56, false, 0.25)]) == 1, true, "triple tap fires once")
check(run(.rightOption, [(61, true, 0), (61, false, 0.05)]) == 1, true, "right Option tap")
check(run(.rightOption, [(61, true, 0), (61, false, 0.05)], deviceBits: false) == 1, true, "right Option, synthetic")
check(run(.rightOption, [(58, true, 0), (58, false, 0.05)]) == 0, true, "left Option ignored")
check(run(.rightOption, [(61, true, 0), (61, false, 0.4)]) == 0, true, "right Option held too long")
check(run(.rightOption, [(61, true, 0), (61, false, 0.1)], cancelAt: 0.05) == 0, true, "right Option + key (⌥-char)")
check(run(.rightOption, [(58, true, 0), (61, true, 0.02), (61, false, 0.06), (58, false, 0.1)]) == 0, true,
      "right Option with left Option held")

// Double Command
check(run(.doubleCommand, double(55)) == 1, true, "double left Command")
check(run(.doubleCommand, double(54)) == 1, true, "double right Command")
check(run(.doubleCommand, double(55), deviceBits: false) == 1, true, "double Command, generic mask only")
check(run(.doubleCommand, [(55, true, 0), (55, false, 0.1), (55, true, 0.3), (55, false, 0.4)], cancelAt: 0.35) == 0,
      true, "Command + key (⌘C) after a tap")
check(run(.doubleShift, double(55)) == 0, true, "double Command doesn't fire double Shift")

// Case hotkey: default, off, conflicts with the layout hotkey
check(CaseHotkey.resolve(stored: nil, layout: .doubleShift) == .doubleCommand, true, "case: default double Command")
check(CaseHotkey.resolve(stored: nil, layout: .doubleCommand) == nil, true, "case: default yields to layout double Command")
check(CaseHotkey.resolve(stored: "off", layout: .doubleShift) == nil, true, "case: off")
check(CaseHotkey.resolve(stored: "doubleControl", layout: .doubleShift) == .doubleControl, true, "case: stored choice")
check(CaseHotkey.resolve(stored: nil, layout: .doubleOption) == .doubleCommand, true, "case: default kept with layout double Option")
check(CaseHotkey.resolve(stored: "doubleOption", layout: .rightOption) == nil, true, "case: right Option conflicts with double Option")
check(CaseHotkey.resolve(stored: "doubleShift", layout: .doubleShift) == nil, true, "case: same hotkey as layout")
check(CaseHotkey.resolve(stored: "garbage", layout: .doubleShift) == nil, true, "case: unknown value is off")
check(Hotkey.doubleShift.conflicts(with: .doubleOption), false, "conflict: Shift vs Option")

// Both detectors see the same events, each fires only on its own modifier
do {
    var layout = TapDetector(), caseD = TapDetector()
    layout.hotkey = .doubleShift; caseD.hotkey = .doubleOption
    var fired: [String] = []
    for (code, down, t) in double(58) + double(56).map({ ($0.0, $0.1, $0.2 + 1) }) {
        let flags = down ? CGEventFlags(rawValue: masks[code]!.rawValue | bits[code]!) : CGEventFlags()
        if layout.flagsChanged(keyCode: code, flags: flags, at: t) { fired.append("layout") }
        if caseD.flagsChanged(keyCode: code, flags: flags, at: t) { fired.append("case") }
    }
    check(fired == ["case", "layout"], true, "two detectors: Option -> case, Shift -> layout")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
