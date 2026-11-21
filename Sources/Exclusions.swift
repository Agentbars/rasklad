import Cocoa

/// Apps where Rasklad stays silent: no key buffering, no reaction to the hotkey.
/// Entries are bundle identifiers; an entry ending in "*" matches by prefix ("com.jetbrains.*").
struct ExclusionList: Equatable {
    private(set) var entries: [String]

    static let defaults = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
        "com.jetbrains.*",           // IntelliJ, PyCharm, WebStorm, ...: double Shift = Search Everywhere
        "com.google.android.studio", // JetBrains-based, same double Shift
    ]

    init(_ entries: [String] = ExclusionList.defaults) { self.entries = entries }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return entries.contains { Self.entry($0, matches: bundleID) }
    }

    /// Excludes the app, or, if it is already excluded, removes every entry that matches it
    /// (including a prefix entry such as "com.jetbrains.*").
    mutating func toggle(_ bundleID: String) {
        if isExcluded(bundleID) {
            entries.removeAll { Self.entry($0, matches: bundleID) }
        } else {
            entries.append(bundleID)
        }
    }

    mutating func remove(_ entry: String) { entries.removeAll { $0 == entry } }

    static func entry(_ entry: String, matches bundleID: String) -> Bool {
        if entry.hasSuffix("*") { return bundleID.hasPrefix(entry.dropLast()) }
        return entry == bundleID
    }
}

/// Keeps the exclusion list in UserDefaults, tracks the frontmost app and builds the menu items.
final class Exclusions: NSObject {
    private static let key = "excludedApps"
    private let defaults: UserDefaults
    private(set) var list: ExclusionList {
        didSet { defaults.set(list.entries, forKey: Self.key); update() }
    }
    /// Last frontmost app other than Rasklad: the one the menu item refers to.
    private(set) var frontApp: NSRunningApplication?
    /// Cached on activation so the key path only reads a Bool.
    private(set) var isFrontExcluded = false
    /// Called with the new `isFrontExcluded` whenever it may have changed.
    var onChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = ExclusionList(defaults.stringArray(forKey: Self.key) ?? ExclusionList.defaults)
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.activated(app)
        }
        activated(NSWorkspace.shared.frontmostApplication)
    }

    private func activated(_ app: NSRunningApplication?) {
        // An LSUIElement app's status menu does not activate it, but Rasklad's own alerts do.
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        frontApp = app
        update()
    }

    private func update() {
        isFrontExcluded = list.isExcluded(frontApp?.bundleIdentifier)
        onChange?(isFrontExcluded)
    }

    // MARK: - Menu

    func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if let app = frontApp, let id = app.bundleIdentifier {
            let name = app.localizedName ?? id
            let toggle = NSMenuItem(title: "Не работать в «\(name)»", action: #selector(toggleFront), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = id
            toggle.state = list.isExcluded(id) ? .on : .off
            items.append(toggle)
        }

        let submenu = NSMenu()
        if list.entries.isEmpty {
            let empty = NSMenuItem(title: "Нет исключений", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            let hint = NSMenuItem(title: "Нажмите, чтобы убрать", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
            for entry in list.entries.sorted(by: { Self.title(for: $0) < Self.title(for: $1) }) {
                let item = NSMenuItem(title: Self.title(for: entry), action: #selector(removeEntry(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry
                item.toolTip = entry
                submenu.addItem(item)
            }
        }
        submenu.addItem(.separator())
        let reset = NSMenuItem(title: "Вернуть список по умолчанию", action: #selector(resetDefaults), keyEquivalent: "")
        reset.target = self
        submenu.addItem(reset)

        let parent = NSMenuItem(title: "Исключения", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        items.append(parent)
        return items
    }

    private static let prefixTitles = ["com.jetbrains.*": "Все JetBrains IDE"]

    /// App name for a bundle id, or the bundle id itself if the app is not installed.
    static func title(for entry: String) -> String {
        if let title = prefixTitles[entry] { return title }
        if entry.hasSuffix("*") { return entry }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return entry
    }

    @objc private func toggleFront(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        list.toggle(id)
    }

    @objc private func removeEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? String else { return }
        list.remove(entry)
    }

    @objc private func resetDefaults() { list = ExclusionList() }
}
