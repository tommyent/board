#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Board.xcodeproj -scheme Board -configuration Release -derivedDataPath build/DerivedData build
python3 Scripts/package_app.py

# Ad-hoc signatures change CDHash every build, so Input Monitoring grants
# do not survive a reinstall. Prefer Developer ID, then a stable local identity.
identity="${BOARD_CODESIGN_IDENTITY:-}"
timestamp="--timestamp=none"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/{print $2; exit}')"
  if [ -n "$identity" ]; then timestamp="--timestamp"; fi
fi
if [ -z "$identity" ]; then
  if security find-identity -v -p codesigning | grep -F -q 'NotAHotDog Signing'; then
    identity="NotAHotDog Signing"
  else
    identity="-"
  fi
fi
ent="$(mktemp)"
trap 'rm -f "$ent"' EXIT
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict></dict></plist>' > "$ent"
if [ "$identity" = "-" ]; then
  /usr/bin/codesign --force --deep --options runtime --sign - --entitlements "$ent" --timestamp=none dist/Board.app
else
  /usr/bin/codesign --force --deep --options runtime --sign "$identity" --entitlements "$ent" "$timestamp" dist/Board.app
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 dist/Board.app
/usr/bin/codesign -d -r- dist/Board.app
