import Cocoa
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = KeyMonitor()
    private let exclusions = Exclusions()
    private var statusItem: NSStatusItem!
    private var retryTimer: Timer?
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); updateIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        monitor.hotkey = Hotkey.current
        monitor.onTrigger = { [weak self] in self?.convert() }
        monitor.caseHotkey = CaseHotkey.current
        monitor.onCaseTrigger = { [weak self] in self?.toggleCase() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.monitor.reset() }
        exclusions.onChange = { [weak self] excluded in self?.monitor.paused = excluded }
        monitor.paused = exclusions.isFrontExcluded

        requestPermissions()
        startMonitor()
        Updates.start()
    }

    // MARK: - Permissions

    private var hasAccessibility: Bool { AXIsProcessTrusted() }

    private func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        log.info("launch: ax=\(AXIsProcessTrusted()) listen=\(CGPreflightListenEventAccess())")
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    }

    private func startMonitor() {
        if monitor.start() && hasAccessibility { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.monitor.start() && self.hasAccessibility { timer.invalidate() }
            self.updateIcon()
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Conversion

    private func convert() {
        log.info("convert: enabled=\(self.enabled) ax=\(self.hasAccessibility) secure=\(IsSecureEventInputEnabled()) buffer=\(self.monitor.buffer.count)")
        guard enabled, hasAccessibility, !IsSecureEventInputEnabled() else { return }
        let layouts = Layouts.enabled()
        guard layouts.count >= 2 else { NSSound.beep(); return }

        guard let range = monitor.run else {
            convertSelection(layouts: layouts)
            return
        }
        let sourceID = monitor.layoutID(at: range.upperBound - 1) ?? Layouts.currentID()
        guard let target = Layouts.next(after: sourceID, in: layouts) else { return }
        let keys = monitor.buffer[range]
        let newText = Converter.retype(keys, in: target)
        let toDelete = keys.reduce(0) { $0 + $1.produced.count }

        TextOutput.backspace(toDelete)
        TextOutput.type(newText.joined())
        monitor.replace(range, with: newText, layoutID: target.id)
        monitor.didConvert(switchingTo: target.id)
        Layouts.select(target)
        Feedback.show(from: sourceID, to: target, in: layouts)
    }

    /// Nothing typed since the last click or arrow key: convert the selected text instead.
    private func convertSelection(layouts: [KeyboardLayout]) {
        withSelection { text in
            guard let result = Converter.convertText(text, layouts: layouts) else { return }
            TextOutput.type(result.text)
            Layouts.select(result.target)
            self.monitor.reset()
            Feedback.show(from: nil, to: result.target, in: layouts)
        }
    }

    /// Copies the selection with ⌘C, hands its text to `body`, then restores the clipboard.
    /// Does nothing when nothing is selected.
    private func withSelection(_ body: @escaping (String) -> Void) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        let before = pasteboard.changeCount
        TextOutput.copy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard pasteboard.changeCount != before else { return } // nothing selected
            defer {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.restore(saved, to: pasteboard) }
            }
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
            body(text)
        }
    }

    // MARK: - Case

    /// Inverts the case of the typing run (or of the selection when nothing was typed).
    /// The layout is not switched.
    private func toggleCase() {
        log.info("case: enabled=\(self.enabled) ax=\(self.hasAccessibility) secure=\(IsSecureEventInputEnabled()) buffer=\(self.monitor.buffer.count)")
        guard enabled, hasAccessibility, !IsSecureEventInputEnabled() else { return }

        guard let range = monitor.run else {
            withSelection { text in
                guard CaseInverter.hasCase(text) else { return }
                TextOutput.type(CaseInverter.invert(text))
                self.monitor.reset()
                Feedback.showCase()
            }
            return
        }
        let keys = monitor.buffer[range]
        let newKeys = CaseInverter.invert(keys)
        guard zip(keys, newKeys).contains(where: { $0.produced != $1.produced }) else { return }
        // Delete and retype from the first changed key only.
        let first = zip(keys.indices, newKeys).first { keys[$0].produced != $1.produced }!.0
        let tail = keys[first...]
        TextOutput.backspace(tail.reduce(0) { $0 + $1.produced.count })
        TextOutput.type(newKeys[(first - range.lowerBound)...].map(\.produced).joined())
        monitor.replaceKeys(range, with: newKeys)
        Feedback.showCase()
    }

    private func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [:]) { dict, type in dict[type] = item.data(forType: type) }
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    // MARK: - Menu

    /// Template keycap with A/Я (Resources/MenuBarIcon*.png, drawn by scripts/make-icons.swift).
    private static let menuBarIcon: NSImage? = {
        let image = Bundle.main.image(forResource: "MenuBarIcon")
        image?.isTemplate = true
        image?.accessibilityDescription = "Rasklad"
        return image
    }()

    private func updateIcon() {
        let ok = monitor.isRunning && hasAccessibility
        statusItem?.button?.image = ok
            ? (Self.menuBarIcon ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Rasklad"))
            : NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Rasklad: нужен доступ")
        statusItem?.button?.appearsDisabled = !enabled
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()
        menu.removeAllItems()

        if !hasAccessibility {
            menu.addItem(item("Дать доступ: Универсальный доступ…", #selector(openAccessibility)))
        }
        if !monitor.isRunning {
            menu.addItem(item("Дать доступ: Мониторинг ввода…", #selector(openInputMonitoring)))
        }
        if !hasAccessibility || !monitor.isRunning {
            // macOS reports newly granted permissions to a running app only after a relaunch.
            menu.addItem(item("Перезапустить Rasklad (после выдачи доступа)", #selector(relaunch)))
        }
        if hasAccessibility && monitor.isRunning {
            let info = NSMenuItem(title: "\(monitor.hotkey.title) — исправить раскладку", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            if let caseHotkey = monitor.caseHotkey {
                let info = NSMenuItem(title: "\(caseHotkey.title) — сменить регистр", action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
        }
        menu.addItem(.separator())

        let toggle = item("Включено", #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)
        exclusions.menuItems().forEach(menu.addItem)

        menu.addItem(hotkeyMenuItem(title: "Горячая клавиша", target: self, action: #selector(chooseHotkey(_:)),
                                    current: monitor.hotkey, taken: monitor.caseHotkey, takenBy: "смена регистра"))
        menu.addItem(hotkeyMenuItem(title: "Смена регистра", target: self, action: #selector(chooseCaseHotkey(_:)),
                                    current: monitor.caseHotkey, allowOff: true,
                                    taken: monitor.hotkey, takenBy: "раскладка"))

        let login = item("Открывать при входе", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        Feedback.menuItems().forEach(menu.addItem)

        menu.addItem(.separator())
        menu.addItem(Updates.menuItem())
        menu.addItem(item("Выйти", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openAccessibility() { openPrivacySettings("Privacy_Accessibility") }
    @objc private func openInputMonitoring() { openPrivacySettings("Privacy_ListenEvent") }
    @objc private func toggleEnabled() { enabled.toggle(); monitor.reset() }
    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let hotkey = Hotkey(rawValue: raw) else { return }
        Hotkey.current = hotkey
        monitor.hotkey = hotkey
        monitor.caseHotkey = CaseHotkey.current // a saved case hotkey that conflicted may be free now
    }
    @objc private func chooseCaseHotkey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        CaseHotkey.current = Hotkey(rawValue: raw) // "off" -> nil
        monitor.caseHotkey = CaseHotkey.current
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не получилось изменить автозапуск"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
