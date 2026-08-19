#!/bin/sh
# Regenerates assets/screenshot.png: the app renders its own status-bar image
# and panel (real pixels, real data, accounts redacted) via `--snapshot`, then
# the pair is composited into a Mac menu-bar frame. No screen-recording or
# accessibility permission involved.
set -e
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

./scripts/bundle.sh >/dev/null
./build/Dipstick.app/Contents/MacOS/Dipstick --snapshot "$WORK"

python3 - "$WORK" <<'PY'
import base64, struct, sys, os

work = sys.argv[1]

def load(p):
    d = open(os.path.join(work, p), 'rb').read()
    w, h = struct.unpack('>II', d[16:24])
    return w, h, base64.b64encode(d).decode()

bw, bh, b64bar = load('bar.png')
pw, ph, b64panel = load('panel.png')
S = 2
barW, barH = bw // S, bh // S
panW, panH = pw // S, ph // S

menuH, margin = 25, 28
H = menuH + 10 + panH + 46
W = H                          # square: qlmanage crops any other aspect

itemX = W - margin - 150 - barW
panX = min(itemX + barW / 2 - panW / 2, W - margin - panW)
panY = menuH + 10

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W*S}" height="{H*S}" viewBox="0 0 {W} {H}">
 <defs>
  <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1">
   <stop offset="0" stop-color="#232837"/><stop offset="0.55" stop-color="#181c26"/><stop offset="1" stop-color="#10121a"/>
  </linearGradient>
  <clipPath id="panclip"><rect x="{panX}" y="{panY}" width="{panW}" height="{panH}" rx="12"/></clipPath>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
   <feDropShadow dx="0" dy="10" stdDeviation="18" flood-color="#000" flood-opacity="0.55"/>
  </filter>
 </defs>
 <rect width="{W}" height="{H}" fill="url(#desk)"/>
 <rect width="{W}" height="{menuH}" fill="#1c1d22" fill-opacity="0.92"/>
 <rect y="{menuH}" width="{W}" height="0.5" fill="#000" fill-opacity="0.4"/>
 <image x="{itemX}" y="{(menuH-barH)/2:.1f}" width="{barW}" height="{barH}" href="data:image/png;base64,{b64bar}"/>
 <g fill="#d8d8dc" fill-opacity="0.85">
  <g transform="translate({W-margin-118},{menuH/2})">
   <path d="M0,2 a10,10 0 0 1 14,0 l-2,2 a7,7 0 0 0 -10,0 z M3,5 a6,6 0 0 1 8,0 l-2,2 a3,3 0 0 0 -4,0 z M6,8 a2,2 0 0 1 2,0 l-1,1.4 z" transform="translate(-7,-5)"/>
  </g>
  <text x="{W-margin-72}" y="{menuH/2+4}" font-family="-apple-system, 'Helvetica Neue'" font-size="11.5" font-weight="500">Wed 4:20 PM</text>
 </g>
 <path d="M {itemX+barW/2-8},{panY} l 8,-7 l 8,7 z" fill="#2a2b31" filter="url(#shadow)"/>
 <g filter="url(#shadow)"><rect x="{panX}" y="{panY}" width="{panW}" height="{panH}" rx="12" fill="#2a2b31"/></g>
 <image x="{panX}" y="{panY}" width="{panW}" height="{panH}" href="data:image/png;base64,{b64panel}" clip-path="url(#panclip)"/>
 <rect x="{panX+0.5}" y="{panY+0.5}" width="{panW-1}" height="{panH-1}" rx="11.5" fill="none" stroke="#ffffff" stroke-opacity="0.09"/>
</svg>'''
open(os.path.join(work, 'screenshot.svg'), 'w').write(svg)
PY

qlmanage -t -s 1440 -o "$WORK" "$WORK/screenshot.svg" >/dev/null 2>&1
[ -f "$WORK/screenshot.svg.png" ] || { echo "qlmanage produced nothing" >&2; exit 1; }
cp "$WORK/screenshot.svg.png" assets/screenshot.png
echo "wrote assets/screenshot.png ($(du -h assets/screenshot.png | cut -f1))"
