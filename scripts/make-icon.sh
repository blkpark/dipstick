#!/bin/sh
# Build Dipstick.icns from assets/icon.svg.
#
# qlmanage is the rasteriser because it is the one macOS already ships: no
# Homebrew dependency standing between a clone and a working app. It writes
# <name>.png beside -o at the requested size, and it keeps the alpha channel,
# which is what the rounded corners need.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/assets/icon.svg"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
iconset="$work/Dipstick.iconset"
mkdir -p "$iconset"

render() {   # px, filename
  qlmanage -t -s "$1" -o "$work" "$src" >/dev/null 2>&1
  [ -f "$work/icon.svg.png" ] || { echo "qlmanage produced no PNG at $1px" >&2; exit 1; }
  sips -z "$1" "$1" "$work/icon.svg.png" --out "$iconset/$2" >/dev/null
  rm -f "$work/icon.svg.png"
}

for s in 16 32 128 256 512; do
  render "$s" "icon_${s}x${s}.png"
  render "$((s * 2))" "icon_${s}x${s}@2x.png"
done

iconutil -c icns "$iconset" -o "$root/assets/Dipstick.icns"
echo "built $root/assets/Dipstick.icns"
