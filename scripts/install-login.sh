#!/bin/sh
# Register Dipstick.app to start at login via a LaunchAgent.
# A LaunchAgent over Login Items because it is scriptable and survives reinstalls
# of the app bundle; remove with: scripts/install-login.sh --remove
set -eu

plist="$HOME/Library/LaunchAgents/dev.blkpark.dipstick.plist"
uid=$(id -u)

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$uid" "$plist" 2>/dev/null || true
  rm -f "$plist"
  echo "removed login item"
  exit 0
fi

app="/Applications/Dipstick.app/Contents/MacOS/Dipstick"
[ -x "$app" ] || { echo "Dipstick.app not found in /Applications — install it first" >&2; exit 1; }

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>dev.blkpark.dipstick</string>
  <key>ProgramArguments</key><array><string>$app</string></array>
  <key>RunAtLoad</key><true/>
  <!-- menu bar app: if it crashes or is quit, launchd does not resurrect it;
       the user quitting from the panel should stay quit -->
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$uid" "$plist" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$plist"
echo "registered: Dipstick starts at login"
