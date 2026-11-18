#!/usr/bin/env bash
# Reproduce unsigned pull-request checks. No install, upload, or app termination.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-validate}"
DERIVED_ROOT="${MONK_DERIVED_DATA:-$ROOT_DIR/.derived-data/ci}"
case "$MODE" in
  validate)
    python3 script/validate_repository.py
    python3 -m unittest discover -s script/tests
    for script in script/*.sh; do bash -n "$script"; done
    ;;
  mobile|mac)
    python3 script/validate_repository.py
    python3 - <<'PY'
import re, subprocess, sys
version=subprocess.check_output(['xcodebuild','-version'], text=True)
match=re.search(r'Xcode (\d+)\.(\d+)', version)
if not match or tuple(map(int,match.groups())) < (26,4):
    sys.exit('Monk requires Xcode 26.4 or newer (FamilyActivityData SDK).')
print(version.strip())
PY
    if [[ "$MODE" == mobile ]]; then
      xcodebuild -project Monk.xcodeproj -scheme Monk -configuration Release \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED_ROOT/mobile" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
    else
      xcodebuild -project Monk.xcodeproj -scheme MonkMac -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$DERIVED_ROOT/mac" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
      xcodebuild -project Monk.xcodeproj -scheme MonkMac -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_ROOT/mac" \
        -resultBundlePath "$DERIVED_ROOT/mac-tests-$(date -u +%Y%m%dT%H%M%SZ).xcresult" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
    fi
    ;;
  *)
    echo "usage: $0 [validate|mobile|mac]" >&2
    exit 2
    ;;
esac
