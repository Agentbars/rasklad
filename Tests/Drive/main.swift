import Carbon
import Foundation

// Live test driver: sends real key presses (with real key codes, like a keyboard does)
// to the frontmost app, so Rasklad sees them exactly as it sees the user's typing.
//
//   drive type ghbdtn     type text using the ABC layout's key codes
//   drive shift2          double-tap Shift
//   drive key <code>      press one key by virtual key code
//   drive select-word     Option+Shift+Left: select the previous word
//
// Usage: swiftc Tests/Drive/main.swift Sources/Layouts.swift -framework Carbon -o build/drive

let source = CGEventSource(stateID: .hidSystemState)

func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
    e.flags = flags
    e.post(tap: .cghidEventTap)
    usleep(12_000)
}

func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
    post(code, down: true, flags: flags)
    post(code, down: false, flags: flags)
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { print("usage: drive type <text> | shift2 | key <code> | select-word"); exit(2) }

switch command {
case "type":
    guard let abc = Layouts.enabled().first(where: { $0.id.hasSuffix(".ABC") || $0.id.hasSuffix(".US") }) else { exit(1) }
    for ch in args.dropFirst().joined(separator: " ") {
        guard let s = abc.reverseMap[ch] else { print("no key for \(ch)"); continue }
        if s.shift { post(56, down: true, flags: .maskShift) }
        press(s.keyCode, flags: s.shift ? .maskShift : [])
        if s.shift { post(56, down: false) }
    }
case "shift2":
    for _ in 0..<2 {
        post(56, down: true, flags: .maskShift)
        usleep(60_000)
        post(56, down: false)
        usleep(100_000)
    }
case "key":
    press(CGKeyCode(args.dropFirst().first.flatMap { UInt16($0) } ?? 0))
case "layout": // drive layout ABC — select a layout by id suffix; no argument prints the current one
    if let suffix = args.dropFirst().first, let l = Layouts.enabled().first(where: { $0.id.hasSuffix(suffix) }) { Layouts.select(l) }
    usleep(200_000)
    print(Layouts.currentID() ?? "?")
case "select-word":
    press(123, flags: [.maskAlternate, .maskShift])
default:
    print("unknown command"); exit(2)
}
