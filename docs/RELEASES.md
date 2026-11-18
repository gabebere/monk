# Apple release engineering

The Apple 1.0 candidate is **not yet a published release**. `Configurations/Version.xcconfig` is the version/build source; `release/1.0.0.json` records the target version, platform artifacts, required evidence, and readiness. Keep every platform `readyForDistribution` false until its actual gates pass.

## Version and artifact model

| Value | Source | Applies to |
| --- | --- | --- |
| Marketing version `1.0.0` | `MONK_VERSION` | Phone, tablet, mobile extensions, Mac |
| Mobile build | `MONK_MOBILE_BUILD` | Universal phone/tablet app and both extensions |
| Mac build | `MONK_MAC_BUILD` | Mac application |
| Source release tag | `v1.0.0` | Reviewed Apple source snapshot |

Use semantic versioning for the Apple product: patch for compatible fixes, minor for compatible features, major for deliberate incompatible behavior/contract changes. Store build numbers must increase monotonically for each artifact. Phone and tablet share one mobile build; do not create separate arbitrary “iPad 1.0” targets or bundle IDs.

A shared source release does not promise simultaneous review/store availability. Release notes state the commit, available mobile/Mac builds, and distribution channels. Windows is excluded and uses its own experimental roadmap.

## Pull-request validation

```sh
./script/ci.sh validate
./script/ci.sh mobile
./script/ci.sh mac
```

The checked-in Apple CI workflow uses separate repository validation, universal mobile build, and Mac build/tests jobs. See the workflow for the selected runner/Xcode version. Pull-request CI is unsigned and must not receive production signing or notarization credentials. A successful unsigned build is necessary but does not prove distribution entitlements, Screen Time enforcement, or real-device sync.

## Signed local artifacts

Configure identifiers/resources using [setup](SETUP.md), then choose new output directories outside source control:

```sh
./script/archive.sh mobile /tmp/monk-mobile-1.0.0-build-2 2
./script/archive.sh mac /tmp/monk-mac-1.0.0-build-2 2
```

The optional third argument is the distributed build number; select a number not already used by that artifact. Archives require a clean working tree by default. `MONK_ALLOW_DIRTY_ARCHIVE=1` permits an explicitly unreviewed local candidate and records that state in provenance; do not use that override for a public release. The scripts validate repository configuration, archive Release, export for App Store Connect or Developer ID with the Production iCloud environment, verify exported metadata, and retain provenance/logs. They **do not upload or publish**. `MONK_ALLOW_PROVISIONING_UPDATES=1` permits Xcode to refresh profiles when deliberately needed; otherwise use already provisioned resources.

A Mac export requires a valid Developer ID Application identity and an iCloud-capable provisioning configuration. Do not work around missing capability approval by stripping entitlements. For mobile, inspect the exported main app and both extensions. `script/verify_export.py` is the export verifier; retain the archive/export evidence locally, and do not attach profiles/certificates to public releases.

## Mac notarization and package

After creating a signed export, use an already configured `notarytool` Keychain profile:

```sh
./script/package_mac.sh \
  /tmp/monk-mac-1.0.0-build-2/export/MonkOS.app \
  /tmp/monk-mac-1.0.0-build-2/package \
  MONK_NOTARY_PROFILE
```

This command performs a real submission to Apple's notary service. It notarizes/staples the app and final DMG, checks the app with Gatekeeper, and writes checksums. It does not create a GitHub release. Keep credentials in the Keychain, and use the profile name rather than placing passwords in shell history or source. A successful notarization must be followed by fresh-machine download/install/launch acceptance.

## Mobile delivery

Upload the verified export using Xcode Organizer or the team's approved App Store Connect delivery tool. Distribution requires Family Controls approval for the main app and relevant extensions, matching profiles/App Group associations, and the Production CloudKit schema. TestFlight acceptance on both phone and tablet precedes a public App Store release. Optional installed-app data access must be tested as a distributed build in relevant regions; development behavior is insufficient.

## Release record and publication

Complete [the release checklist](runbooks/RELEASE_CHECKLIST.md) for the final source SHA. Update the manifest with non-sensitive evidence references: CI run, schema deployment date, builds, signed artifact verification, device matrix, checksums, release owner, and known limitations. Preserve the manifest's distinction between source readiness and actual published availability.

Only after approval, tag the reviewed commit and create/publish release notes. Include installation instructions and actual supported behavior, particularly worldwide local app selection and optional automatic naming. Never publish private CloudKit exports, raw local state, signing credentials, provisioning profiles, or debug archives. Do not call an unsigned CI artifact an installer.

## Rollback and support

Keep the last verified Mac artifact and checksum available. An App Store update rollback normally means shipping a newer build containing the compatible fix; do not promise installation of an older store binary. CloudKit Production migrations are additive and cannot be undone by deleting fields already used by clients. Prefer a forward fix and retain compatibility readers. Do not reset the private database to recover one client. Document emergency limitations and block further rollout while preserving active local commitments.
