#!/bin/bash
# Relaunch a macOS app stuck as "damaged" (or hanging at launch) without reinstalling:
# clone it to a new path, re-sign the clone ad hoc, open the clone.
# Usage: ./fix-damaged-app.sh "/path/to/App.app" ["New Name"]
set -euo pipefail

app="${1:?usage: $0 /path/to/App.app [\"New Name\"]}"
app="${app%/}"
[ -d "$app/Contents" ] || { echo "Not an app bundle: $app" >&2; exit 1; }

name="$(basename "$app" .app)"
dest="$(dirname "$app")/${2:-$name 2}.app"
[ -e "$dest" ] && { echo "Already exists: $dest" >&2; exit 1; }

exe="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
if pgrep -x "$exe" >/dev/null; then
  echo "\"$exe\" is running (possibly stuck). Quit it first: pkill -x \"$exe\"" >&2
  exit 1
fi

echo "Cloning to: $dest"
# APFS clone: instant, no extra space. Falls back to a full copy on other file systems.
cp -Rc "$app" "$dest" 2>/dev/null || ditto "$app" "$dest"

echo "Re-signing the clone ad hoc..."
codesign --force --deep --sign - "$dest"
codesign --verify --deep --strict "$dest"

echo "Opening (first launch runs a fresh Gatekeeper scan, ~15 s for a large app)..."
open "$dest"
echo "Once it works, you can delete the original: $app"
