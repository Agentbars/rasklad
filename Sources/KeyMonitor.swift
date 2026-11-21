import Cocoa
import Carbon

/// Watches the keyboard (listen-only), remembers what was typed since the last
/// click / arrow / shortcut, and fires `onTrigger` on a double tap of Shift.
final class KeyMonitor {
    var onTrigger: (() -> Void)?
    private(set) var buffer: [TypedKey] = []
    private(set) var bufferLayouts: [String] = [] // layout id each key was typed in
    private var tap: CFMachPort?
    private var currentLayoutID: String? = Layouts.currentID()

    private var shiftDownAt: TimeInterval?
    private var shiftClean = false
    private var lastShiftTapAt: TimeInterval = 0

    static let doubleTapInterval: TimeInterval = 0.45
    static let maxTapLength: TimeInterval = 0.3

    var isRunning: Bool { tap != nil }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.currentLayoutID = Layouts.currentID() }
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .listenOnly, eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func reset() {
        buffer.removeAll()
        bufferLayouts.removeAll()
    }

    /// Records the result of a conversion so the next press converts it again.
    func replace(_ range: Range<Int>, with strings: [String], layoutID: String) {
        for (i, s) in zip(range, strings) {
            buffer[i].produced = s
            bufferLayouts[i] = layoutID
        }
    }

    func layoutID(at index: Int) -> String? {
        bufferLayouts.indices.contains(index) ? bufferLayouts[index] : nil
    }

    // MARK: - Events

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        default: break
        }
        if event.getIntegerValueField(.eventSourceUserData) == TextOutput.marker { return }

        switch type {
        case .keyDown:
            shiftClean = false
            lastShiftTapAt = 0
            handleKey(event)
        case .flagsChanged:
            handleFlags(event)
        default: // mouse click: the caret may have moved
            shiftClean = false
            lastShiftTapAt = 0
            reset()
        }
    }

    private static let resetKeys: Set<UInt16> = [
        36, 76, 48, 53,          // return, enter, tab, escape
        117, 115, 119, 116, 121, // fwd delete, home, end, page up, page down
        123, 124, 125, 126,      // arrows
    ]

    private func handleKey(_ event: CGEvent) {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) { reset(); return }
        if code == 51 { // backspace
            if flags.contains(.maskAlternate) || buffer.isEmpty { reset() } else {
                buffer.removeLast()
                bufferLayouts.removeLast()
            }
            return
        }
        if Self.resetKeys.contains(code) { reset(); return }

        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let produced = String(utf16CodeUnits: chars, count: length)
        let nonText = produced.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || (0xF700...0xF8FF).contains($0.value) // F-keys etc.
        }
        if nonText { reset(); return }

        let stroke = KeyStroke(keyCode: code,
                               shift: flags.contains(.maskShift),
                               option: flags.contains(.maskAlternate),
                               capsLock: flags.contains(.maskAlphaShift))
        buffer.append(TypedKey(stroke: stroke, produced: produced))
        bufferLayouts.append(currentLayoutID ?? "")
        if buffer.count > 300 {
            buffer.removeFirst(100)
            bufferLayouts.removeFirst(100)
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let now = ProcessInfo.processInfo.systemUptime
        guard code == 56 || code == 60 else { // not left/right Shift
            shiftClean = false
            lastShiftTapAt = 0
            return
        }
        if flags.contains(.maskShift) { // pressed
            shiftClean = flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
            shiftDownAt = now
            return
        }
        // released
        defer { shiftClean = false }
        guard shiftClean, let down = shiftDownAt, now - down < Self.maxTapLength else {
            lastShiftTapAt = 0
            return
        }
        if lastShiftTapAt > 0, now - lastShiftTapAt < Self.doubleTapInterval {
            lastShiftTapAt = 0
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        } else {
            lastShiftTapAt = now
        }
    }
}
