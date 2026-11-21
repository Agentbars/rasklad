import Cocoa

/// Shows that a conversion happened: a short system sound and a small "EN → RU" (or "Aa") hint
/// near the text caret (or the mouse pointer when the caret position is unknown).
/// Both can be switched off in the menu; settings live in UserDefaults.
enum Feedback {
    private static let soundKey = "feedbackSound"
    private static let hintKey = "feedbackHint"

    static var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    static var hintEnabled: Bool {
        get { UserDefaults.standard.object(forKey: hintKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hintKey) }
    }

    /// Call after a conversion that actually changed text.
    /// `fromID` is the layout the text was typed in; nil means "the one before `target`".
    static func show(from fromID: String?, to target: KeyboardLayout, in layouts: [KeyboardLayout]) {
        if soundEnabled { playSound() }
        guard hintEnabled else { return }
        let source = layouts.first { $0.id == fromID } ?? previous(before: target, in: layouts)
        let text = "\(source.map(label(for:)) ?? "?") → \(label(for: target))"
        // Synthetic keystrokes are delivered asynchronously: let the app move its caret first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { HintPanel.shared.show(text) }
    }

    /// Call after a case inversion that changed text: same sound, hint `Aa`.
    static func showCase() {
        if soundEnabled { playSound() }
        guard hintEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { HintPanel.shared.show("Aa") }
    }

    /// Menu checkboxes for the status bar menu.
    static func menuItems() -> [NSMenuItem] {
        [
            MenuTarget.shared.item("Звук при исправлении", #selector(MenuTarget.toggleSound), on: soundEnabled),
            MenuTarget.shared.item("Подсказка на экране", #selector(MenuTarget.toggleHint), on: hintEnabled),
        ]
    }

    /// Short label: ABC/US → EN, Russian → RU, otherwise the first letters of the layout name.
    static func label(for layout: KeyboardLayout) -> String {
        let id = layout.id.components(separatedBy: ".").last ?? layout.id
        let english = ["ABC", "US", "British", "Australian", "Canadian", "Irish", "Dvorak", "Colemak"]
        if english.contains(where: { id.hasPrefix($0) }) { return "EN" }
        if id.hasPrefix("Russian") { return "RU" }
        let letters = layout.name.filter { $0.isLetter }
        return letters.isEmpty ? "?" : String(letters.prefix(2)).uppercased()
    }

    private static func previous(before target: KeyboardLayout, in layouts: [KeyboardLayout]) -> KeyboardLayout? {
        guard let i = layouts.firstIndex(where: { $0.id == target.id }), layouts.count > 1 else { return nil }
        return layouts[(i + layouts.count - 1) % layouts.count]
    }

    private static func playSound() {
        guard let sound = NSSound(named: "Tink") else { return }
        sound.stop() // the named sound is shared: restart it on quick repeated conversions
        sound.volume = 0.5
        sound.play()
    }

    // MARK: - Caret position

    /// Caret rectangle in Cocoa screen coordinates (origin bottom-left), via Accessibility.
    static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1) // never hang on an unresponsive app
        guard let focused: AXUIElement = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.1)
        guard let rangeValue: AXValue = attribute(focused, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }

        // Many apps return an empty rect for a zero-length range: fall back to the character before the caret.
        var candidates = [range]
        if range.length == 0 && range.location > 0 { candidates.append(CFRange(location: range.location - 1, length: 1)) }
        for candidate in candidates {
            var r = candidate
            guard let param = AXValueCreate(.cfRange, &r) else { continue }
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                focused, kAXBoundsForRangeParameterizedAttribute as CFString, param, &result) == .success,
                  let value = result, CFGetTypeID(value) == AXValueGetTypeID() else { continue }
            var rect = CGRect.zero
            guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0 else { continue }
            if candidate.location != range.location { rect.origin.x += rect.width } // caret is after that char
            rect.size.width = max(rect.width, 1)
            return flipped(rect)
        }
        return nil
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Accessibility uses top-left origin of the primary screen; Cocoa uses bottom-left.
    private static func flipped(_ rect: CGRect) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let r = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        // Reject garbage (some apps report 0,0 or off-screen bounds).
        guard r.origin != .zero, NSScreen.screens.contains(where: { $0.frame.intersects(r) }) else { return nil }
        return r
    }
}

/// Target for the menu checkboxes (enum Feedback cannot be an Objective-C target).
private final class MenuTarget: NSObject {
    static let shared = MenuTarget()

    func item(_ title: String, _ action: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc func toggleSound() { Feedback.soundEnabled.toggle() }
    @objc func toggleHint() { Feedback.hintEnabled.toggle() }
}

/// Borderless, click-through panel that never becomes key or activates Rasklad.
private final class HintPanel: NSPanel {
    static let shared = HintPanel()

    private let label = NSTextField(labelWithString: "")
    private var generation = 0

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 80, height: 28),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // .hudWindow material follows light/dark appearance automatically.
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        contentView = background
    }

    func show(_ text: String) {
        generation += 1
        let current = generation
        label.stringValue = text
        let size = NSSize(width: ceil(label.intrinsicContentSize.width) + 20, height: 26)
        setFrame(NSRect(origin: origin(for: size), size: size), display: true)

        alphaValue = 1
        orderFrontRegardless() // shows without activating Rasklad or taking focus

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.generation == current else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == current else { return }
                self.orderOut(nil)
            })
        }
    }

    /// Just below the caret, or below-right of the mouse pointer; kept inside the screen.
    private func origin(for size: NSSize) -> NSPoint {
        var point: NSPoint
        if let caret = Feedback.caretRect() {
            point = NSPoint(x: caret.minX, y: caret.minY - size.height - 4)
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x + 14, y: mouse.y - size.height - 14)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            point.x = min(max(point.x, frame.minX + 4), frame.maxX - size.width - 4)
            if point.y < frame.minY + 4 { point.y += size.height + 30 } // no room below: go above
            point.y = min(max(point.y, frame.minY + 4), frame.maxY - size.height - 4)
        }
        return point
    }
}
