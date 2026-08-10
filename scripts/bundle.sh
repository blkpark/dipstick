#!/bin/sh
# Build Dipstick.app. A menu bar app needs a bundle with LSUIElement so it stays
# out of the Dock and the app switcher; SwiftPM only produces a bare binary.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
app="${1:-$root/build/Dipstick.app}"

swift build -c release --package-path "$root"
binary="$root/.build/release/Dipstick"
[ -x "$binary" ] || { echo "build produced no binary at $binary" >&2; exit 1; }

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Dipstick"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dipstick</string>
  <key>CFBundleDisplayName</key><string>Dipstick</string>
  <key>CFBundleIdentifier</key><string>dev.blkpark.dipstick</string>
  <key>CFBundleExecutable</key><string>Dipstick</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3.1</string>
  <key>CFBundleVersion</key><string>9</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- menu bar only: no Dock icon, no app switcher entry -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for the app to run locally. Distributing it to other
# machines needs a Developer ID and notarisation.
codesign --force --sign - "$app" >/dev/null 2>&1 || \
  echo "note: ad-hoc signing failed; the app still runs locally" >&2

echo "built $app"
