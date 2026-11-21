#!/bin/zsh
# Builds Rasklad.app (universal: Apple Silicon + Intel) into ./build.
#   ./build.sh install   also copies it to ~/Applications and launches it
#   VERSION=1.2.3 ./build.sh   sets the app version (used by the release workflow)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Rasklad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
mkdir -p "$APP/Contents/Resources"
cp Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# App icon: Icon Composer bundle -> Assets.car (macOS 26+) and AppIcon.icns (older macOS).
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist build/actool-partial.plist >/dev/null

for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $ARCH-apple-macos13.0 \
    -framework Cocoa -framework Carbon -framework ServiceManagement \
    Sources/*.swift -o "build/Rasklad-$ARCH"
done
lipo -create build/Rasklad-arm64 build/Rasklad-x86_64 -output "$APP/Contents/MacOS/Rasklad"

# Sign with the local certificate from scripts/make-signing-cert.sh if it exists:
# then macOS keeps permissions across rebuilds. Otherwise ad-hoc (permissions reset each build).
IDENTITY="Rasklad Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "warning: \"$IDENTITY\" not found, signing ad-hoc. Run scripts/make-signing-cert.sh once."
  codesign --force --sign - "$APP"
fi
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x Rasklad || true
  rm -rf ~/Applications/Rasklad.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Rasklad.app
  echo "Installed to ~/Applications/Rasklad.app"
fi
