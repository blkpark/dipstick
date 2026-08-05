#!/bin/sh
# Build a distributable DMG: Dipstick.app + an /Applications shortcut, plus the
# CLI and its installer, since the app is a readout over the CLI and useless
# without it. hdiutil only -- no packaging dependencies.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# Build first: reading the version off the previous bundle stamps every image
# with the last release's number.
"$root/scripts/bundle.sh" >/dev/null
version=$(defaults read "$root/build/Dipstick.app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo dev)
cp -R "$root/build/Dipstick.app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir "$stage/CLI"
cp "$root/tools/dipstick" "$stage/CLI/dipstick"
cp "$root/scripts/install-login.sh" "$stage/CLI/"
cp "$root/README.md" "$root/README_KOR.md" "$stage/"
cat > "$stage/CLI/INSTALL.txt" <<'TXT'
1. Drag Dipstick.app into Applications.
2. Install the CLI the app reads from:
     install -m 755 CLI/dipstick ~/.local/bin/dipstick
3. Optional, start at login:
     sh CLI/install-login.sh
The app is ad-hoc signed: on first open, right-click the app > Open.
TXT

out="$root/build/Dipstick-$version.dmg"
rm -f "$out"
hdiutil create -volname "Dipstick" -srcfolder "$stage" -ov -format UDZO "$out" >/dev/null
echo "$out"
