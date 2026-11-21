import Cocoa
import Carbon

/// Watches the keyboard (listen-only), remembers what was typed since the last
/// click / arrow / shortcut, and fires `onTrigger` on the chosen hotkey (see Hotkey.swift).
final class KeyMonitor {
    var onTrigger: (() -> Void)?
    private(set) var buffer: [TypedKey] = []
    private(set) var bufferLayouts: [String] = [] // layout id each key was typed in
    private var tap: CFMachPort?
    private var currentLayoutID: String? = Layouts.currentID()
    private var typingRun = TypingRun()
    /// Layout Rasklad itself is switching to; that switch must not clear the buffer.
    private var ownSwitchTarget: String?

    private var tapDetector = TapDetector()
    var hotkey: Hotkey {
        get { tapDetector.hotkey }
        set { tapDetector.hotkey = newValue }
    }

    var isRunning: Bool { tap != nil }

    /// Set while an excluded app is frontmost: keys are neither buffered nor checked for the hotkey.
    var paused = false {
        didSet { if paused { reset(); tapDetector.cancel() } }
    }

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.layoutChanged() }
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        // Without Input Monitoring a tap can still be created but never receives events.
        guard CGPreflightListenEventAccess() else { return false }
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
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log.error("event tap: create failed (Input Monitoring not granted?)")
            return false
        }
        log.info("event tap: started")
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func reset() {
        buffer.removeAll()
        bufferLayouts.removeAll()
        typingRun.reset()
    }

    /// What the hotkey converts now: the typing run (see `TypingRun`).
    var run: Range<Int>? { typingRun.range(in: buffer) }

    /// Call after converting `run` and before switching the layout to `layoutID`.
    func didConvert(switchingTo layoutID: String) {
        typingRun.didConvert()
        ownSwitchTarget = layoutID
    }

    /// A manual layout switch starts a new run; Rasklad's own switch after a conversion does not.
    private func layoutChanged() {
        currentLayoutID = Layouts.currentID()
        if let own = ownSwitchTarget, own == currentLayoutID {
            ownSwitchTarget = nil
            return
        }
        ownSwitchTarget = nil
        if !buffer.isEmpty { log.debug("layout switched by hand: buffer cleared") }
        reset()
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
            log.error("event tap: disabled by system (\(type.rawValue)), re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        default: break
        }
        if paused || event.getIntegerValueField(.eventSourceUserData) == TextOutput.marker { return }

        switch type {
        case .keyDown:
            tapDetector.cancel()
            handleKey(event)
        case .flagsChanged:
            handleFlags(event)
        default: // mouse click: the caret may have moved
            tapDetector.cancel()
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
                typingRun.didShrink(to: buffer.count)
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
        typingRun.willType(at: buffer.count)
        buffer.append(TypedKey(stroke: stroke, produced: produced))
        log.debug("key: buffered, buffer=\(self.buffer.count)")
        bufferLayouts.append(currentLayoutID ?? "")
        if buffer.count > 2000 {
            buffer.removeFirst(500)
            bufferLayouts.removeFirst(500)
            typingRun.didDropFirst(500)
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        log.debug("flags: key=\(code) flags=\(String(flags.rawValue, radix: 16))")
        if tapDetector.flagsChanged(keyCode: code, flags: flags, at: ProcessInfo.processInfo.systemUptime) {
            log.info("hotkey: \(self.hotkey.rawValue)")
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        }
    }
}
