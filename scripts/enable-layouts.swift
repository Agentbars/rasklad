// CI helper: enables the Russian keyboard layout so the conversion tests can run.
//   swift scripts/enable-layouts.swift
import Carbon

let filter = [kTISPropertyInputSourceID: "com.apple.keylayout.Russian"] as CFDictionary
guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
      let russian = list.first else { print("Russian layout not found"); exit(1) }
let status = TISEnableInputSource(russian)
print(status == noErr ? "Russian layout enabled" : "TISEnableInputSource failed: \(status)")
exit(status == noErr ? 0 : 1)
