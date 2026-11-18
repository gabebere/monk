#!/usr/bin/env bash
# Execute the real policy/service XCTest suites without launching Monk or building UI assets.
# This complements a full Xcode build; it does not verify UI, signing or device enforcement.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/monk-core-tests.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
DEVELOPER_TEST_DIR="$(xcode-select -p)/Platforms/MacOSX.platform/Developer"

SOURCES=(
  Shared/*.swift
  MonkMac/Models/*.swift
  MonkMac/Stores/*.swift
  MonkMac/Services/ApplicationCatalog.swift
  MonkMac/Services/ApplicationGuardian.swift
  MonkMac/Services/BrowserWebsiteGuardian.swift
  MonkMac/Services/CalendarFocusRecorder.swift
  MonkMac/Services/CrossDeviceFocusSyncService.swift
  MonkMac/Services/GlobalHotKeyController.swift
  MonkMac/Services/LaunchAtLoginController.swift
  MonkMac/Services/WebsiteHistorySuggestionService.swift
)

xcrun swiftc -swift-version 5 -module-cache-path "$CHECK_DIR/cache" \
  -emit-module -emit-library -enable-testing -module-name MonkMac \
  -emit-module-path "$CHECK_DIR/MonkMac.swiftmodule" \
  -o "$CHECK_DIR/libMonkMac.dylib" "${SOURCES[@]}"

python3 - "$CHECK_DIR/main.swift" <<'PY'
from pathlib import Path
import re
import sys
classes = []
for path in sorted(Path('MonkMacTests').glob('*.swift')):
    classes.extend(re.findall(r'^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b', path.read_text(), re.M))
if not classes:
    sys.exit('No XCTest suites were found; refusing an empty test run.')
Path(sys.argv[1]).write_text(
    'import XCTest\nimport Foundation\n'
    'let suite = XCTestSuite(name: "Monk core regression suite")\n'
    + ''.join(f'suite.addTest({name}.defaultTestSuite)\n' for name in classes)
    + 'suite.run()\n'
    'guard let run = suite.testRun, run.executionCount > 0, run.hasSucceeded else { exit(1) }\n'
)
PY

xcrun swiftc -swift-version 5 -module-cache-path "$CHECK_DIR/cache" \
  -I "$CHECK_DIR" -L "$CHECK_DIR" -lMonkMac \
  -I "$DEVELOPER_TEST_DIR/usr/lib" -L "$DEVELOPER_TEST_DIR/usr/lib" \
  -F "$DEVELOPER_TEST_DIR/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$CHECK_DIR" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_TEST_DIR/usr/lib" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_TEST_DIR/Library/Frameworks" \
  MonkMacTests/*.swift "$CHECK_DIR/main.swift" -o "$CHECK_DIR/MonkCoreTests"
"$CHECK_DIR/MonkCoreTests"
