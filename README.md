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

Typed keys are remembered only since the last click, arrow key, Return or shortcut, and only
in memory. Nothing is stored or sent anywhere.

## Build

Requires macOS 13+ and Xcode (or the Command Line Tools).

```bash
./build.sh install
```

This builds `build/Rasklad.app`, copies it to `~/Applications` and launches it.
On first launch grant **Accessibility** and **Input Monitoring** in
System Settings → Privacy & Security. The app is ad-hoc signed, so macOS asks again after
every rebuild.

## Tests

```bash
swiftc -swift-version 5 -framework Carbon -framework Cocoa Sources/Layouts.swift Sources/Converter.swift Tests/main.swift -o build/tests && ./build/tests
```

The tests use the layouts enabled on your Mac and expect ABC (or US) and Russian.

## Code

| File | What it does |
| --- | --- |
| `Sources/Layouts.swift` | Enabled layouts, key → character via `UCKeyTranslate`, reverse maps |
| `Sources/Converter.swift` | Last-word detection and text conversion (pure logic) |
| `Sources/KeyMonitor.swift` | Listen-only event tap, typed-keys buffer, double-Shift detection |
| `Sources/TextOutput.swift` | Synthetic backspaces and Unicode typing |
| `Sources/main.swift` | Menu bar UI, permissions, launch at login |
