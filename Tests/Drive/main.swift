import Cocoa
import Carbon

// Live test driver: sends real key presses (with real key codes, like a keyboard does)
// to the frontmost app, so Rasklad sees them exactly as it sees the user's typing.
// Used by scripts/e2e.sh; the process that runs it needs Accessibility to post events.
//
//   drive type ghbdtn          type text using the ABC layout's key codes
//   drive shift2               double-tap Shift
//   drive tap <hotkey>         doubleShift | doubleOption | doubleControl | rightOption
//   drive key <code>           press one key by virtual key code
//   drive select-word          Option+Shift+Left: select the previous word
//   drive click <x> <y>        left click at a global display point (top-left origin)
//   drive layout [suffix]      select a layout by id suffix; prints the current layout id
//   drive host <command>       send a command to the e2e host app (clear, focus-text, focus-secure)
//   drive check                exit 1 if this process may not post key events (Accessibility)
//   drive clip-set <text>      put plain text on the clipboard
//   drive clip-get             print the clipboard's plain text
//   drive clip-save <file>     save every clipboard item and type to a file
//   drive clip-restore <file>  put a saved clipboard back
//
// Build: swiftc Tests/Drive/main.swift Sources/Layouts.swift -framework Carbon -framework Cocoa -o build/drive

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

/// A clean tap of a modifier key: flagsChanged down, then up.
func tapModifier(_ code: CGKeyCode, _ mask: CGEventFlags, times: Int) {
    for _ in 0..<times {
        post(code, down: true, flags: mask)
        usleep(60_000)
        post(code, down: false)
        usleep(100_000)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { print("usage: see Tests/Drive/main.swift"); exit(2) }
let rest = Array(args.dropFirst())

switch command {
case "check":
    if !CGPreflightPostEventAccess() { _ = CGRequestPostEventAccess(); exit(1) }
case "type":
    guard let abc = Layouts.enabled().first(where: { $0.id.hasSuffix(".ABC") || $0.id.hasSuffix(".US") }) else { exit(1) }
    for ch in rest.joined(separator: " ") {
        guard let s = abc.reverseMap[ch] else { print("no key for \(ch)"); continue }
        if s.shift { post(56, down: true, flags: .maskShift) }
        press(s.keyCode, flags: s.shift ? .maskShift : [])
        if s.shift { post(56, down: false) }
    }
case "shift2":
    tapModifier(56, .maskShift, times: 2)
case "tap":
    switch rest.first ?? "" {
    case "doubleShift": tapModifier(56, .maskShift, times: 2)
    case "doubleOption": tapModifier(58, .maskAlternate, times: 2)
    case "doubleControl": tapModifier(59, .maskControl, times: 2)
    case "rightOption": tapModifier(61, .maskAlternate, times: 1)
    default: print("unknown hotkey"); exit(2)
    }
case "key":
    press(CGKeyCode(rest.first.flatMap { UInt16($0) } ?? 0))
case "select-word":
    press(123, flags: [.maskAlternate, .maskShift])
case "click":
    guard rest.count == 2, let x = Double(rest[0]), let y = Double(rest[1]) else { exit(2) }
    let point = CGPoint(x: x, y: y)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { continue }
        e.setIntegerValueField(.mouseEventClickState, value: 1) // never a double click
        e.post(tap: .cghidEventTap)
        usleep(40_000)
    }
case "layout":
    if let suffix = rest.first, let l = Layouts.enabled().first(where: { $0.id.hasSuffix(suffix) }) { Layouts.select(l) }
    usleep(200_000)
    print(Layouts.currentID() ?? "?")
case "layouts":
    Layouts.enabled().forEach { print($0.id) }
case "host":
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.rasklad.e2e.host"), object: rest.first, userInfo: nil, deliverImmediately: true)
    usleep(150_000)
case "clip-set":
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(rest.joined(separator: " "), forType: .string)
case "clip-get":
    print(NSPasteboard.general.string(forType: .string) ?? "", terminator: "")
case "clip-save":
    guard let path = rest.first else { exit(2) }
    let items: [[String: Data]] = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        item.types.reduce(into: [:]) { dict, type in dict[type.rawValue] = item.data(forType: type) }
    }
    let data = try! PropertyListSerialization.data(fromPropertyList: items, format: .binary, options: 0)
    try! data.write(to: URL(fileURLWithPath: path))
case "clip-restore":
    guard let path = rest.first, let data = FileManager.default.contents(atPath: path),
          let items = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Data]] else { exit(1) }
    NSPasteboard.general.clearContents()
    let objects = items.map { dict -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, value) in dict { item.setData(value, forType: NSPasteboard.PasteboardType(type)) }
        return item
    }
    if !objects.isEmpty { NSPasteboard.general.writeObjects(objects) }
default:
    print("unknown command"); exit(2)
}
