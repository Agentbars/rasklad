import Cocoa

// E2E test host: a window with a text view and a password field whose contents the
// e2e runner can read. Bundle id local.rasklad.e2e-host (see scripts/e2e.sh).
//
//   RaskladE2EHost <out-dir>
//
// Writes, on every change:
//   <out-dir>/text.txt     the text view's contents
//   <out-dir>/secure.txt   the password field's contents
//   <out-dir>/click.txt    "x y": a point inside the text view below the text, in global
//                          display coordinates (top-left origin), for the driver's clicks
// Commands arrive as distributed notifications "local.rasklad.e2e.host" with the command
// as the object: clear, focus-text, focus-secure.

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)

final class Host: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    let window = NSWindow(contentRect: NSRect(x: 80, y: 200, width: 520, height: 300),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let textView = NSTextView(frame: NSRect(x: 10, y: 50, width: 500, height: 240))
    let secure = NSSecureTextField(frame: NSRect(x: 10, y: 12, width: 500, height: 26))

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Rasklad E2E Host"
        window.level = .floating // stay above other windows so the driver's clicks land here
        textView.font = .systemFont(ofSize: 16)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.delegate = self
        secure.delegate = self
        window.contentView?.addSubview(textView)
        window.contentView?.addSubview(secure)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)

        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.rasklad.e2e.host"), object: nil, queue: .main
        ) { [weak self] note in self?.command(note.object as? String ?? "") }
        writeAll()
    }

    func command(_ name: String) {
        switch name {
        case "clear":
            textView.string = ""
            secure.stringValue = ""
        case "focus-text": window.makeFirstResponder(textView)
        case "focus-secure": window.makeFirstResponder(secure)
        default: break
        }
        writeAll()
    }

    func textDidChange(_ notification: Notification) { writeAll() }
    func controlTextDidChange(_ obj: Notification) { writeAll() }

    func writeAll() {
        write("text.txt", textView.string)
        write("secure.txt", secure.stringValue)
        // Below the text, inside the text view: a click there puts the caret at the end.
        let rect = window.convertToScreen(textView.convert(textView.bounds, to: nil))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let x = Int(rect.midX), y = Int(primaryHeight - (rect.minY + 30))
        write("click.txt", "\(x) \(y)")
        write("ready", "")
    }

    func write(_ name: String, _ text: String) {
        try? text.write(to: outDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}

/// Edit menu, so ⌘C / ⌘V / ⌘A reach the text view as in a real app (Rasklad copies the selection with ⌘C).
func mainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let appMenu = NSMenu(title: "RaskladE2EHost")
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let menu = NSMenu()
    for sub in [appMenu, edit] {
        let item = NSMenuItem()
        item.submenu = sub
        menu.addItem(item)
    }
    return menu
}

let app = NSApplication.shared
app.mainMenu = mainMenu()
let host = Host()
app.delegate = host
app.setActivationPolicy(.regular)
app.run()
