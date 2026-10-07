#!/usr/bin/env bash
#
# Builds NTS.app from the SPM executable. No Xcode required: `swift build` plus a
# hand-assembled bundle, ad-hoc signed so macOS will run it locally.
#
# Output: ./build/NTS.app
#
# UNIVERSAL=1 builds for Apple Silicon and Intel instead of only this Mac's architecture.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="NTS"
BUNDLE_ID="nl.sanderjanssen.nts"
VERSION="${VERSION:-1.0.0}"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building with swift build"
BINARIES=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Building both architectures in one go needs Xcode, one at a time does not.
    for ARCH in arm64 x86_64; do
        swift build -c release --product "$APP_NAME" --triple "$ARCH-apple-macosx14.0"
        BINARIES+=("$(swift build -c release --product "$APP_NAME" --triple "$ARCH-apple-macosx14.0" --show-bin-path)/$APP_NAME")
    done
else
    swift build -c release --product "$APP_NAME"
    BINARIES+=("$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME")
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT"/Resources/* "$CONTENTS/Resources/"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>NTS looks for Cast devices on your network to play on.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_googlecast._tcp</string>
    </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

echo "==> Done: $APP_DIR"
