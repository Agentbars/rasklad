#!/bin/zsh
# Builds Rasklad.app (universal: Apple Silicon + Intel) into ./build.
#   ./build.sh install   also copies it to ~/Applications and launches it
#   VERSION=1.2.3 ./build.sh   sets the app version (used by the release workflow)
#   SIGN_IDENTITY="Rasklad Release Signing" ./build.sh   signs with that certificate (release workflow)
set -euo pipefail
cd "$(dirname "$0")"

# Sparkle (auto-updates): pinned official release, verified by SHA-256, cached in build/deps.
SPARKLE_VERSION=2.10.1
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE=build/deps/Sparkle-$SPARKLE_VERSION
if [[ ! -d "$SPARKLE/Sparkle.framework" ]]; then
  mkdir -p build/deps
  ARCHIVE=build/deps/Sparkle-$SPARKLE_VERSION.tar.xz
  curl -fsSL -o "$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c --quiet
  rm -rf "$SPARKLE" && mkdir -p "$SPARKLE"
  tar -xJf "$ARCHIVE" -C "$SPARKLE"
  rm "$ARCHIVE"
fi

APP=build/Rasklad.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  # Sparkle compares CFBundleVersion, so both carry the release version.
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
  plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
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
    -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/*.swift -o "build/Rasklad-$ARCH"
done
lipo -create build/Rasklad-arm64 build/Rasklad-x86_64 -output "$APP/Contents/MacOS/Rasklad"

# Embed Sparkle. The XPC services are only needed by sandboxed apps; Rasklad is not sandboxed.
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"

# Signing: SIGN_IDENTITY if given (release), else the local certificate from
# scripts/make-signing-cert.sh if it exists, so macOS keeps permissions across rebuilds;
# otherwise ad-hoc (permissions reset each build). Nested code first, the app last.
IDENTITY="${SIGN_IDENTITY:-Rasklad Local Signing}"
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "error: signing identity \"$SIGN_IDENTITY\" not found" >&2
    exit 1
  fi
  echo "warning: \"$IDENTITY\" not found, signing ad-hoc. Run scripts/make-signing-cert.sh once."
  IDENTITY=-
fi
sign() { codesign --force --sign "$IDENTITY" "$@"; }
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x Rasklad || true
  rm -rf ~/Applications/Rasklad.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/Rasklad.app
  echo "Installed to ~/Applications/Rasklad.app"
fi
