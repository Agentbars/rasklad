#!/bin/zsh
# Builds Rasklad.app into ./build. "./build.sh install" also copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Rasklad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework Cocoa -framework Carbon -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/Rasklad"

# Ad-hoc signature: macOS asks for permissions again after each rebuild.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x Rasklad || true
  rm -rf ~/Applications/Rasklad.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Rasklad.app
  echo "Installed to ~/Applications/Rasklad.app"
fi
