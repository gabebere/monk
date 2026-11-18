# 005 — Repeatable Apple distribution and production configuration

Priority: P1 release gate. Status: release tooling implemented and static/export-verifier tests passing; Apple resource approval, actual signed exports, notarization, and publication remain unverified.

## Problem and evidence

The original `script/build_and_run.sh` built Debug and copied MonkOS to `~/Applications` for the developer. It did not produce a distributable signed artifact. The repository had no Apple CI workflow, explicit shared Mac scheme, export configuration, notarization/package script, release manifest, or centralized version/build source. App and extension versions were repeated in `Monk.xcodeproj/project.pbxproj`.

The entitlements referenced one configurable iCloud container and mobile App Group, which is a sound base. However, checked-in entitlement strings do not prove that matching Apple resources, distribution capability approvals, profiles, certificates, or production schema exist. `docs/SETUP.md` described manual release requirements without a reproducible operational handoff.

## Required delivery model

Phone and tablet remain one universal App Store/TestFlight artifact with one synchronized mobile/extension build number. Mac remains a separate Developer ID signed, hardened-runtime, notarized artifact distributed directly. Use one Apple source semver/tag and track per-platform readiness/build numbers. Produce archives and exports through project-owned commands, fail clearly on missing configuration, inspect final signed entitlements, and separate artifact creation from upload/publication.

CI must build both Apple targets and run meaningful tests without requiring production secrets for pull requests. Signed release operations use narrowly scoped credentials provided outside source control. The release checklist must verify Family Controls approval for the app and relevant Screen Time extensions, App Group association, the shared iCloud container, Production schema deployment, and consistent CloudKit environment across installed artifacts.

## Migration and rollout

Preserve existing bundle IDs, App Group, container, and user data unless an explicit product migration is approved. A change in marketing version must not create a new app identity. Build numbers must monotonically increase for each distributed artifact. Deploy additive CloudKit schema changes before releasing clients that require them; promotion copies schema, not user records. Do not tag or publish a 1.0 release while gates are incomplete.

## Candidate remediation

Version/build settings are centralized in `Configurations/Version.xcconfig`; `release/1.0.0.json` records three platform surfaces and unresolved evidence. Explicit shared Mac test/archive scheme and Apple CI jobs cover source validation and both app targets. `script/archive.sh` produces local signed archives/exports with provenance and `verify_export.py` checks. `script/package_mac.sh` performs deliberate notarization/stapling, Gatekeeper checks, DMG creation, and checksums. The development launcher remains separate and respects active enforcement. Repository/export tooling has focused Python tests; actual signed exports, notarization, and Apple resource approvals were not executed in this environment.

## Acceptance evidence

Static configuration validator; clean checkout CI; signed mobile archive/export containing both extensions; successful TestFlight installation on phone and tablet; signed universal Mac archive/export, notarization ticket, Gatekeeper assessment, and fresh-machine launch; matching version/build information; Production sync across all three surfaces. Store artifact checksums, commit SHA, build numbers, CI URL, and test evidence with release records, without credentials or private user data.

References: [Family Controls distribution](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement), [CloudKit schema deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema), and [Mac notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
