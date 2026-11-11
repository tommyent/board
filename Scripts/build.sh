#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
notarize=0
case "${1:-}" in
  "") ;;
  --notarize) notarize=1 ;;
  *) echo "usage: bash Scripts/build.sh [--notarize]" >&2; exit 2 ;;
esac
xcodebuild -project Board.xcodeproj -scheme Board -configuration Release -derivedDataPath build/DerivedData build
python3 Scripts/package_app.py
# Debug symbols carry the build folder's absolute path, home folder included. Remove them before signing.
strip -S dist/Board.app/Contents/MacOS/Board
if /usr/bin/grep -a -q '/Users/' dist/Board.app/Contents/MacOS/Board; then
  echo "error: the binary still contains a /Users/ path" >&2
  exit 1
fi
# Board only listens, AI mode included: fail if the app links any API that posts events into other apps.
if nm -u dist/Board.app/Contents/MacOS/Board | grep -E '^_(CGEventPost|CGEventPostToPid|CGEventPostToPSN|CGEventTapPostEvent|CGPostKeyboardEvent|CGPostMouseEvent|AXUIElementPostKeyboardEvent)$'; then
  echo "error: Board links an event-posting API" >&2
  exit 1
fi

# Ad-hoc signatures change CDHash every build, so Input Monitoring grants
# do not survive a reinstall. Prefer Developer ID, then a stable local identity.
identities="$(security find-identity -v -p codesigning)"
identity="${BOARD_CODESIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(awk '/"Developer ID Application:/{print $2; exit}' <<<"$identities")"
fi
# BOARD_CODESIGN_IDENTITY counts as Developer ID when it is that identity's hash or full name.
developer_id=0
if [ -n "$identity" ] && awk -v id="$identity" '$2 == id || index($0, "\"" id "\"")' <<<"$identities" | grep -q '"Developer ID Application:'; then
  developer_id=1
fi
if [ "$developer_id" = 0 ]; then
  if [ "$notarize" = 1 ]; then
    echo "error: --notarize needs a Developer ID Application identity; none found${BOARD_CODESIGN_IDENTITY:+ (BOARD_CODESIGN_IDENTITY is not one)}." >&2
    exit 1
  fi
  if [ -z "$identity" ]; then
    if grep -F -q '"NotAHotDog Signing"' <<<"$identities"; then identity="NotAHotDog Signing"; else identity="-"; fi
  fi
  {
    echo
    echo "******************************************************************"
    echo "WARNING: not signing with Developer ID. Using: $identity ('-' is ad-hoc)."
    echo "This build is for this Mac only: Gatekeeper rejects it on other Macs"
    echo "and it cannot be notarized."
    echo "******************************************************************"
    echo
  } >&2
fi
timestamp="--timestamp=none"
if [ "$developer_id" = 1 ]; then timestamp="--timestamp"; fi
ent="$(mktemp)"
trap 'rm -f "$ent"' EXIT
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict></dict></plist>' > "$ent"
/usr/bin/codesign --force --deep --options runtime --sign "$identity" --entitlements "$ent" "$timestamp" dist/Board.app
/usr/bin/codesign --verify --deep --strict --verbose=2 dist/Board.app
/usr/bin/codesign -d -r- dist/Board.app

# Off unless asked for: uploads the app to Apple's notary service. One-time setup is in README.md.
if [ "$notarize" = 1 ]; then
  profile="${BOARD_NOTARY_PROFILE:-board-notary}"
  archive="build/Board-notarize.zip"
  /usr/bin/ditto -c -k --keepParent dist/Board.app "$archive"
  echo "Submitting $archive to Apple's notary service with keychain profile '$profile'…"
  result="$(xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait --timeout 1h --output-format json)" || true
  id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - - <<<"$result" 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    printf '%s\n' "$result" >&2
    echo "error: notarization status: ${status:-unknown (submission failed or timed out)}." >&2
    if [ -n "$id" ]; then
      echo "Notary log for $id:" >&2
      xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
    fi
    exit 1
  fi
  echo "Notarization accepted ($id). Stapling…"
  xcrun stapler staple dist/Board.app
  xcrun stapler validate dist/Board.app
  /usr/sbin/spctl -a -vvv -t exec dist/Board.app
fi
