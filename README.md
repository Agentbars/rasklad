# Rasklad

A tiny macOS menu bar app that fixes text typed in the wrong keyboard layout.
Typed `ghbdtn` instead of `привет`? Double-tap **Shift** and it's fixed.

Маленькое приложение для macOS: исправляет текст, набранный не в той раскладке, по двойному нажатию Shift.

## How it works

- **Last word.** Double-tap Shift right after typing: the last word is erased, re-typed as if
  the same keys were pressed in the other layout, and the input source is switched.
  Double-tap again to switch it back.
- **Selection.** Select text (mouse or Shift+arrows), then double-tap Shift: the selection is
  converted. The clipboard is restored afterwards.
- Works with any layouts enabled in System Settings (ABC, Russian, ...). With more than two,
  repeated taps cycle through them.
- Password fields are never touched (macOS secure input).
- **Excluded apps.** In excluded apps Rasklad neither remembers keys nor reacts to double Shift.
  Menu → «Не работать в «…»» toggles the app you were in; «Исключения» lists them (click to remove).
  By default: Terminal, iTerm2, Warp, Ghostty, kitty, Alacritty, WezTerm, all JetBrains IDEs
  (`com.jetbrains.*`, where double Shift is Search Everywhere) and Android Studio.

Typed keys are remembered only since the last click, arrow key, Return or shortcut, and only
in memory. Nothing is stored or sent anywhere.

## Build

Requires macOS 13+ and Xcode (or the Command Line Tools).

```bash
./build.sh install
```

This builds `build/Rasklad.app`, copies it to `~/Applications` and launches it.
On first launch grant **Accessibility** and **Input Monitoring** in
System Settings → Privacy & Security, then relaunch Rasklad.

To keep those permissions across rebuilds, create a local signing certificate once:

```bash
scripts/make-signing-cert.sh
```

Without it the app is signed ad-hoc and macOS asks for permissions again after every rebuild.

## Tests

```bash
swiftc -swift-version 5 -framework Carbon -framework Cocoa Sources/Layouts.swift Sources/Converter.swift Sources/Exclusions.swift Tests/main.swift -o build/tests && ./build/tests
```

The tests use the layouts enabled on your Mac and expect ABC (or US) and Russian.

## Troubleshooting

Logs (no typed characters, only event kinds and counts):

```bash
/usr/bin/log stream --predicate 'subsystem == "local.rasklad"' --level debug
```

If `launch: ax=false listen=false` stays even though Rasklad is switched on in System Settings,
the switch belongs to an older build. Reset it and grant again, then relaunch:

```bash
tccutil reset All local.rasklad
```

Newly granted permissions are picked up only after Rasklad is relaunched.

## Code

| File | What it does |
| --- | --- |
| `Sources/Layouts.swift` | Enabled layouts, key → character via `UCKeyTranslate`, reverse maps |
| `Sources/Converter.swift` | Last-word detection and text conversion (pure logic) |
| `Sources/KeyMonitor.swift` | Listen-only event tap, typed-keys buffer, double-Shift detection |
| `Sources/Exclusions.swift` | Per-app exclusions: list (pure logic), storage, frontmost app, menu items |
| `Sources/TextOutput.swift` | Synthetic backspaces and Unicode typing |
| `Sources/main.swift` | Menu bar UI, permissions, launch at login |

## License

MIT, see [LICENSE](LICENSE).
