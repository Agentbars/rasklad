import Cocoa

/// A modifier key that can be tapped on its own.
enum Modifier: CaseIterable {
    case shift, option, control, command

    var keyCodes: (left: Int64, right: Int64) {
        switch self {
        case .shift: return (56, 60)
        case .option: return (58, 61)
        case .control: return (59, 62)
        case .command: return (55, 54)
        }
    }

    var mask: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }

    static func of(keyCode: Int64) -> (Modifier, isRight: Bool)? {
        for m in allCases {
            if keyCode == m.keyCodes.left { return (m, false) }
            if keyCode == m.keyCodes.right { return (m, true) }
        }
        return nil
    }

    /// Device-dependent flag bit (NX_DEVICE*KEYMASK) telling whether this exact key is down.
    /// The generic mask alone can't tell "right Option released" from "left Option still held".
    static func deviceBit(keyCode: Int64) -> UInt64? {
        switch keyCode {
        case 59: return 0x0001 // left control
        case 56: return 0x0002 // left shift
        case 60: return 0x0004 // right shift
        case 55: return 0x0008 // left command
        case 54: return 0x0010 // right command
        case 58: return 0x0020 // left option
        case 61: return 0x0040 // right option
        case 62: return 0x2000 // right control
        default: return nil
        }
    }

    static let allMasks: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
}

/// The trigger the user picked in the menu. Saved in UserDefaults under `hotkey`.
enum Hotkey: String, CaseIterable {
    case doubleShift, doubleOption, doubleControl, rightOption

    static let defaultsKey = "hotkey"

    static var current: Hotkey {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(Hotkey.init(rawValue:)) ?? .doubleShift }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Menu title.
    var title: String {
        switch self {
        case .doubleShift: return "Двойной Shift"
        case .doubleOption: return "Двойной Option"
        case .doubleControl: return "Двойной Control"
        case .rightOption: return "Правый Option"
        }
    }

    var modifier: Modifier {
        switch self {
        case .doubleShift: return .shift
        case .doubleOption, .rightOption: return .option
        case .doubleControl: return .control
        }
    }

    /// Taps needed to fire.
    var taps: Int { self == .rightOption ? 1 : 2 }

    /// Only this side counts (nil: either side).
    var rightSideOnly: Bool { self == .rightOption }
}

/// Detects a clean tap (or double tap) of a modifier key from `flagsChanged` events.
/// Clean: no other key, click or modifier between press and release; short: held < 0.3 s;
/// for a double tap the second release comes within 0.45 s of the first.
struct TapDetector {
    var hotkey: Hotkey = .doubleShift { didSet { cancel() } }

    static let doubleTapInterval: TimeInterval = 0.45
    static let maxTapLength: TimeInterval = 0.3

    private var downAt: TimeInterval?
    private var clean = false
    private var lastTapAt: TimeInterval = 0

    /// Any key press or mouse click: the current tap doesn't count.
    mutating func cancel() {
        clean = false
        downAt = nil
        lastTapAt = 0
    }

    /// Feed a `flagsChanged` event. Returns true when the hotkey fires.
    mutating func flagsChanged(keyCode: Int64, flags: CGEventFlags, at now: TimeInterval) -> Bool {
        guard let (modifier, isRight) = Modifier.of(keyCode: keyCode),
              modifier == hotkey.modifier, !hotkey.rightSideOnly || isRight,
              let bit = Modifier.deviceBit(keyCode: keyCode) else {
            cancel() // another modifier, Caps Lock, Fn...
            return false
        }
        // Synthetic events may carry only the generic mask, without device bits.
        let sideBits = bit | Self.otherSideBit(keyCode)
        let isDown = flags.rawValue & sideBits != 0 ? flags.rawValue & bit != 0 : flags.contains(modifier.mask)
        if isDown { // pressed
            clean = flags.intersection(Modifier.allMasks.subtracting(modifier.mask)).isEmpty
                && flags.rawValue & Self.otherSideBit(keyCode) == 0
            downAt = now
            return false
        }
        // released
        defer { clean = false; downAt = nil }
        guard clean, let down = downAt, now - down < Self.maxTapLength else {
            lastTapAt = 0
            return false
        }
        if hotkey.taps == 1 { return true }
        if lastTapAt > 0, now - lastTapAt < Self.doubleTapInterval {
            lastTapAt = 0
            return true
        }
        lastTapAt = now
        return false
    }

    /// The same modifier on the other side held as well: not a clean tap.
    private static func otherSideBit(_ keyCode: Int64) -> UInt64 {
        guard let (m, isRight) = Modifier.of(keyCode: keyCode) else { return 0 }
        return Modifier.deviceBit(keyCode: isRight ? m.keyCodes.left : m.keyCodes.right) ?? 0
    }
}

extension Hotkey {
    /// Two hotkeys on the same modifier can't coexist (double Option vs right Option
    /// would both fire on the same taps).
    func conflicts(with other: Hotkey) -> Bool { modifier == other.modifier }
}

/// The second action, case inversion. Saved in UserDefaults under `caseHotkey`
/// as a Hotkey raw value or "off"; double Option by default.
enum CaseHotkey {
    static let defaultsKey = "caseHotkey"
    static let off = "off"
    static let defaultValue: Hotkey = .doubleOption

    /// Effective hotkey: nil when switched off or when it conflicts with the layout
    /// hotkey (the layout hotkey wins, e.g. for users who picked double Option for it).
    static func resolve(stored: String?, layout: Hotkey) -> Hotkey? {
        let hotkey: Hotkey?
        if let stored { hotkey = Hotkey(rawValue: stored) } else { hotkey = defaultValue }
        guard let hotkey, !hotkey.conflicts(with: layout) else { return nil }
        return hotkey
    }

    static var current: Hotkey? {
        get { resolve(stored: UserDefaults.standard.string(forKey: defaultsKey), layout: Hotkey.current) }
        set { UserDefaults.standard.set(newValue?.rawValue ?? off, forKey: defaultsKey) }
    }
}

/// Hotkey submenu with a checkmark on the current choice. Each item carries the Hotkey raw
/// value (or `CaseHotkey.off`) in `representedObject`. Options on the same modifier as
/// `taken` (the other action's hotkey) are disabled and say who holds them.
func hotkeyMenuItem(title: String, target: AnyObject, action: Selector, current: Hotkey?,
                    allowOff: Bool = false, taken: Hotkey? = nil, takenBy: String = "") -> NSMenuItem {
    let submenu = NSMenu()
    submenu.autoenablesItems = false
    for hotkey in Hotkey.allCases {
        let blocked = taken.map(hotkey.conflicts(with:)) ?? false
        let item = NSMenuItem(title: blocked ? "\(hotkey.title) (занято: \(takenBy))" : hotkey.title,
                              action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = hotkey.rawValue
        item.state = hotkey == current ? .on : .off
        item.isEnabled = !blocked
        submenu.addItem(item)
    }
    if allowOff {
        submenu.addItem(.separator())
        let item = NSMenuItem(title: "Выключено", action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = CaseHotkey.off
        item.state = current == nil ? .on : .off
        submenu.addItem(item)
    }
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    parent.submenu = submenu
    return parent
}
