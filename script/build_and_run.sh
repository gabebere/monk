#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SCHEME="MonkMac"
APP_NAME="MonkOS"
LEGACY_PROCESS_NAME="MonkMac"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="${TMPDIR:-/tmp}"
DERIVED_DATA_DIR="${TEMP_ROOT%/}/MonkDerivedData/MonkOS"
# Read all JSON before selecting the app target: an early-exiting awk under
# pipefail can SIGPIPE xcodebuild and abort before the build even starts.
BUNDLE_ID="$(xcodebuild -project "$ROOT_DIR/Monk.xcodeproj" -scheme "$SCHEME" \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" -showBuildSettings -json | python3 -c '
import json, sys
items = json.load(sys.stdin)
settings = next((item["buildSettings"] for item in items if item["target"] == "MonkMac"), {})
identifier = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
if not identifier:
    sys.exit("Xcode could not resolve the MonkMac bundle identifier.")
print(identifier)
')"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
USER_APPLICATIONS_DIR="${HOME}/Applications"
INSTALLED_APP="$USER_APPLICATIONS_DIR/MonkOS.app"
LEGACY_INSTALLED_APP="$USER_APPLICATIONS_DIR/Monk.app"
INSTALLED_BINARY="$INSTALLED_APP/Contents/MacOS/$APP_NAME"

if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..30}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1 && ! pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1 || pgrep -x "$LEGACY_PROCESS_NAME" >/dev/null 2>&1; then
    echo "MonkOS is enforcing an active focus or default block and refused to quit. End the focus or temporarily disable default blocking before relaunching." >&2
    exit 3
  fi
fi

xcodebuild \
  -project "$ROOT_DIR/Monk.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

mkdir -p "$USER_APPLICATIONS_DIR"
if [[ -d "$LEGACY_INSTALLED_APP" && ! -e "$INSTALLED_APP" ]]; then
  /bin/mv "$LEGACY_INSTALLED_APP" "$INSTALLED_APP"
fi
/usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP"
if ! /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"; then
  /bin/rm -rf "$INSTALLED_APP"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALLED_APP"
  /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP"
fi

open_app() {
  /usr/bin/open -n "$INSTALLED_APP"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALLED_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
