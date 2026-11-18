#!/usr/bin/env bash
# Explicitly submit a local Mac export to Apple's notary service, then package it.
# Authentication is read from an existing notarytool keychain profile; never pass secrets.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-}"
OUTPUT_DIR="${2:-}"
NOTARY_PROFILE="${3:-}"
if [[ -z "$APP" || -z "$OUTPUT_DIR" || -z "$NOTARY_PROFILE" || ! -d "$APP/Contents" ]]; then
  echo "usage: $0 EXPORTED_APP OUTPUT_DIR NOTARY_KEYCHAIN_PROFILE" >&2
  exit 2
fi
if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Output already exists; choose a new directory: $OUTPUT_DIR" >&2
  exit 2
fi
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
STAGE="$OUTPUT_DIR/staging"
mkdir -p "$STAGE"
/usr/bin/ditto "$APP" "$STAGE/MonkOS.app"
python3 "$ROOT_DIR/script/verify_export.py" mac "$STAGE" "$BUILD"
/usr/bin/ditto -c -k --keepParent "$STAGE/MonkOS.app" "$OUTPUT_DIR/MonkOS-notarization.zip"
xcrun notarytool submit "$OUTPUT_DIR/MonkOS-notarization.zip" \
  --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$OUTPUT_DIR/app-notarization.json"
python3 - "$OUTPUT_DIR/app-notarization.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted': sys.exit('App notarization was not accepted; inspect app-notarization.json and the notary log.')
PY
xcrun stapler staple "$STAGE/MonkOS.app"
xcrun stapler validate "$STAGE/MonkOS.app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$STAGE/MonkOS.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUTPUT_DIR/MonkOS-$VERSION-$BUILD.dmg"
/usr/bin/hdiutil create -volname MonkOS -srcfolder "$STAGE" -format UDZO "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
  --wait --output-format json > "$OUTPUT_DIR/dmg-notarization.json"
python3 - "$OUTPUT_DIR/dmg-notarization.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted': sys.exit('DMG notarization was not accepted; inspect dmg-notarization.json and the notary log.')
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
/usr/bin/shasum -a 256 "$DMG" > "$OUTPUT_DIR/SHA256SUMS"
echo "Notarized local package: $DMG"
echo "Nothing has been published. Test a downloaded copy on a fresh Mac before release."
