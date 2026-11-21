#!/bin/zsh
# Runs all unit tests. The conversion tests need the ABC (or US) and Russian layouts enabled.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -framework Carbon -framework Cocoa \
  Sources/Layouts.swift Sources/Converter.swift Sources/Exclusions.swift Tests/main.swift -o build/tests
swiftc -swift-version 5 -framework Cocoa Sources/Hotkey.swift Tests/Hotkey/main.swift -o build/hotkey-tests
./build/tests
./build/hotkey-tests
