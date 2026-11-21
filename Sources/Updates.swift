import Cocoa
import Sparkle

/// Auto-updates via Sparkle. Feed, public key and the daily automatic check are set in Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`).
enum Updates {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    static func start() { _ = controller }

    static func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Проверить обновления…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        return item
    }
}
