# Apple 1.0 release checklist

Status: **open**. This checklist is an evidence template, not completed acceptance. Fill references for the exact final commit; do not infer completion from code or configuration files.

## Release identity

| Item | Evidence to record |
| --- | --- |
| Source SHA and tag candidate | SHA; proposed `v1.0.0`; reviewed PR |
| Version | Resolved `MONK_VERSION` and exported marketing versions |
| Mobile build | One increasing number for phone/tablet and extensions |
| Mac build | Increasing Mac artifact number |
| Owner/date | Actual approving maintainer and date |
| Known limitations | Release-note links, affected platforms, practical workaround |

## Repository and automation

- [ ] Final source SHA has passing `Repository validation`, `iPhone and iPad build`, and `Mac build and tests` checks.
- [ ] Live repository protections audited; record controls actually applied, plan restrictions, and any documented bypass.
- [ ] Version manifest and changelog agree with exported artifacts.
- [ ] No credentials, local token data, private record exports, or build artifacts entered source control.

## Apple resources and schema

- [ ] Explicit mobile/Mac bundle IDs remain associated with the intended developer team.
- [ ] Family Controls **distribution** approved for the app and both relevant Screen Time extensions.
- [ ] Mobile App Group associated with app/extensions; final signed entitlements match.
- [ ] Both applications associated with the same intended CloudKit container.
- [ ] Production schema includes additive default-authority and catalog device/version fields plus working catalog-query/subscription indexes.
- [ ] TestFlight/mobile and Developer ID/Mac builds use the intended Production environment.
- [ ] Account A's private records are inaccessible to account B, and pending writes do not cross accounts.

## Artifacts and installation

- [ ] Mobile signed archive/export verified; both extensions present with matching version/build.
- [ ] Phone TestFlight clean install and upgrade accepted: [phone checklist](../platforms/IPHONE.md).
- [ ] Tablet TestFlight clean install and upgrade accepted: [tablet checklist](../platforms/IPAD.md).
- [ ] Mac signed export, hardened runtime, expected architectures, iCloud profile and entitlements verified.
- [ ] Notarization accepted; app and DMG stapled; checksums retained.
- [ ] Downloaded Mac artifact passes Gatekeeper and fresh-machine first launch: [Mac checklist](../platforms/MAC.md).

## Shared behavior

- [ ] Same-account start/extend/expiry/finish round trip across phone, tablet, and Mac.
- [ ] An active commitment never ends early through UI, stale cloud end, or app relaunch.
- [ ] Offline mutations survive force quit and retry after reconnect.
- [ ] Simultaneous independent sessions converge according to the documented whole-policy conflict rule without shortening a deadline.
- [ ] Non-EU distributed mobile builds use local token selection; unresolved remote apps can be mapped explicitly.
- [ ] Remote defaults with incomplete/zero matches preserve local exceptions.
- [ ] Two devices of the same platform retain separate catalogs; ambiguous app names do not grant arbitrary access.
- [ ] Upgrade and mixed-version compatibility checked; any unsupported combinations documented.
- [ ] Permission denial/revocation and OS background restrictions produce understandable recoverable behavior.

## Final decision

- [ ] Required manifest evidence references populated and platform readiness set only where proven.
- [ ] Release owner approves the concrete artifacts and limitations.
- [ ] Tag and release published only after approval; record actual App Store/TestFlight/Mac availability separately.

Use dedicated test accounts/devices and redact account identifiers, intention text, selected apps, and private domains from public evidence.
