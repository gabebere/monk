#!/usr/bin/env bash
# Produce a signed local archive/export. This script never uploads to App Store Connect.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
PLATFORM="${1:-}"
OUTPUT_DIR="${2:-}"
BUILD_NUMBER="${3:-}"
if [[ "$PLATFORM" != mobile && "$PLATFORM" != mac ]] || [[ -z "$OUTPUT_DIR" ]]; then
  echo "usage: $0 {mobile|mac} OUTPUT_DIR [BUILD_NUMBER]" >&2
  echo "Optional: MONK_ALLOW_PROVISIONING_UPDATES=1 permits Xcode to refresh profiles." >&2
  exit 2
fi
python3 script/validate_repository.py
if [[ -n "$(git status --porcelain)" && "${MONK_ALLOW_DIRTY_ARCHIVE:-0}" != 1 ]]; then
  echo "Release archives require a clean reviewed commit. For an explicitly unreviewed local candidate, set MONK_ALLOW_DIRTY_ARCHIVE=1." >&2
  exit 3
fi
if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Output already exists; choose a new directory: $OUTPUT_DIR" >&2
  exit 2
fi
if [[ "$PLATFORM" == mobile ]]; then
  SCHEME=Monk
  DESTINATION='generic/platform=iOS'
else
  SCHEME=MonkMac
  DESTINATION='generic/platform=macOS'
  if ! security find-identity -v -p codesigning | /usr/bin/grep -q 'Developer ID Application:'; then
    echo "A valid Developer ID Application signing identity is required in your keychain." >&2
    exit 3
  fi
fi
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
xcodebuild -project Monk.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination "$DESTINATION" -derivedDataPath "$OUTPUT_DIR/DerivedData" -showBuildSettings -json > "$OUTPUT_DIR/build-settings.json" \
  2> "$OUTPUT_DIR/build-settings.log"
export MONK_ARCHIVE_PLATFORM="$PLATFORM" MONK_ARCHIVE_OUTPUT="$OUTPUT_DIR" MONK_ARCHIVE_BUILD="$BUILD_NUMBER"
python3 - <<'PY'
import json, os, pathlib, plistlib, re, subprocess, sys
root=pathlib.Path(os.environ['MONK_ARCHIVE_OUTPUT'])
platform=os.environ['MONK_ARCHIVE_PLATFORM']
target='Monk' if platform=='mobile' else 'MonkMac'
settings=next(x['buildSettings'] for x in json.loads((root/'build-settings.json').read_text()) if x['target']==target)
if not settings: sys.exit('Xcode could not resolve build settings; inspect build-settings.log and build-settings.json.')
team=settings.get('DEVELOPMENT_TEAM','')
if not re.fullmatch(r'[A-Z0-9]{10}',team): sys.exit('Configure a valid MONK_DEVELOPMENT_TEAM in Configurations/Local.xcconfig.')
version=settings['MARKETING_VERSION']
manifest=json.loads(pathlib.Path('release/1.0.0.json').read_text())
if version!=manifest['version']: sys.exit('Resolved version differs from the release manifest.')
build=os.environ['MONK_ARCHIVE_BUILD'] or settings['CURRENT_PROJECT_VERSION']
if not re.fullmatch(r'[1-9][0-9]*',build): sys.exit('BUILD_NUMBER must be a positive integer.')
options={
    'method': 'app-store-connect' if platform=='mobile' else 'developer-id',
    'destination':'export',
    'teamID':team,
    'signingStyle':'automatic',
    'iCloudContainerEnvironment':'Production',
}
if platform=='mobile':
    options.update(uploadSymbols=True, manageAppVersionAndBuildNumber=False)
else:
    options['signingCertificate']='Developer ID Application'
(root/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
(root/'build-number.txt').write_text(build)
(root/'provenance.json').write_text(json.dumps({
    'version':version, 'build':build, 'platform':platform,
    'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'workingTreeDirty':bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip()),
    'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
    'distributionStatus':'local-export-only',
},indent=2)+'\n')
PY
BUILD_NUMBER="$(cat "$OUTPUT_DIR/build-number.txt")"
ARCHIVE_COMMAND=(xcodebuild -project Monk.xcodeproj -scheme "$SCHEME" -configuration Release
  -destination "$DESTINATION" -archivePath "$OUTPUT_DIR/$SCHEME.xcarchive"
  -derivedDataPath "$OUTPUT_DIR/DerivedData" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
EXPORT_COMMAND=(xcodebuild -exportArchive -archivePath "$OUTPUT_DIR/$SCHEME.xcarchive"
  -exportPath "$OUTPUT_DIR/export" -exportOptionsPlist "$OUTPUT_DIR/ExportOptions.plist")
if [[ "${MONK_ALLOW_PROVISIONING_UPDATES:-0}" == 1 ]]; then
  ARCHIVE_COMMAND+=(-allowProvisioningUpdates)
  EXPORT_COMMAND+=(-allowProvisioningUpdates)
fi
if [[ "$PLATFORM" == mac ]]; then
  ARCHIVE_COMMAND+=(CODE_SIGN_IDENTITY='Developer ID Application')
fi
ARCHIVE_COMMAND+=(archive)
"${ARCHIVE_COMMAND[@]}" 2>&1 | tee "$OUTPUT_DIR/archive.log"
"${EXPORT_COMMAND[@]}" 2>&1 | tee "$OUTPUT_DIR/export.log"
python3 script/verify_export.py "$PLATFORM" "$OUTPUT_DIR/export" "$BUILD_NUMBER"
echo "Signed local export: $OUTPUT_DIR/export"
echo "No release was uploaded or published. Retain provenance.json with the release evidence."
