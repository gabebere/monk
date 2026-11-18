# Verification matrix

A passing source-level check proves only its stated layer. Release readiness requires the final commit's automated checks plus signed artifacts and real-device evidence. No App Store, notarization, Production schema, or fresh-device gate is marked complete merely because its tooling exists.

## Automated coverage

| Layer | Command or source | Expected evidence |
| --- | --- | --- |
| Repository contract | `./script/ci.sh validate` | Version/build, target/scheme, manifest, script/configuration consistency |
| GitHub configuration tooling | `python3 -m unittest discover -s script/tests` | Offline plan/audit/apply behavior without unintended live mutation |
| Universal mobile compile | `./script/ci.sh mobile` | App and embedded extension compile under selected SDK |
| Mac build and tests | `./script/ci.sh mac` | App build plus policy/parser/model/persistence tests |
| Isolated core suite | `./script/test_core.sh` | Actual Mac service/model and shared-contract XCTest cases, without starting the app or compiling UI/assets |
| Portable identity/catalog | `MonkMacTests/CatalogIdentityTests.swift` | Distinct bundle identities, aliases, legacy reads, malformed catalogs, multi-device merge |
| Shared sync policy/journal | Tests alongside the 1.0 sync changes | Extension/end ordering, conflicting sessions, queue coalescing/account behavior |
| Signed export | `script/verify_export.py` through archive tooling | Expected artifacts, entitlements/profile, version/build |
| Mac package | `script/package_mac.sh` | Notarization, stapling, Gatekeeper assessment, checksums |

The repository validator and **17 Python tests** (GitHub governance and signed-export verification) passed during development. The integrated core suite compiled the actual non-UI Mac services/models and shared contract, then ran **87 XCTest cases with zero failures**, including all 17 catalog/identity and 19 shared-sync tests. The mobile services, models, and shared code also passed an iOS 18.5-targeted typecheck against the installed SDK. Modified UI and composition source passed syntax parsing. Xcode resolved both app versions to 1.0.0 (build 1) with the expected IDs and minimum runtimes. These checks do not certify a full app/UI build or signed installation. Both normal platform build attempts remained blocked in icon export in the execution environment; no signed exports or notarization were executed. Record final integrated CI separately.

## Real-device scenarios

| Scenario | Devices | Pass condition |
| --- | --- | --- |
| Start/extend/finish | Phone, tablet, Mac | Same commitment and deadline; local equivalents enforced; no early finish |
| Offline replay | Each source platform | Pending change survives app termination, then converges after reconnect/foreground |
| Concurrent independent starts | At least phone and Mac | Documented whole-policy winner on all peers; no shorter active deadline |
| Stale end after extension | Two or more peers | Earlier end cannot terminate the extended commitment |
| Unavailable installed-app data | Non-EU distributed phone/tablet | Apple's picker works; local selection remains; remote mapping is actionable |
| Incomplete defaults match | Phone/tablet plus Mac | Existing local exceptions survive zero/partial matches |
| Same-platform catalogs | Two Macs or two phones | Separate records remain; neither overwrites the other |
| Ambiguous app names | Platform with duplicate names | No arbitrary name-based access grant |
| Account change | Dedicated accounts A and B | No pending A payload written to B; active local policy remains safe |
| Permission changes | Each platform | Denial/revocation/recovery is understandable; no false “fully synced” claim |
| Upgrade | Prior saved state to candidate | Tokens, mappings, selections, and active commitment retained |
| Fresh installation | Phone/tablet TestFlight, downloaded Mac | Required permissions/install path/signature behave correctly |
| Tablet layouts | Portrait, landscape, split/resizable | All controls remain usable |

Use dedicated test accounts and redact private selections/intention/domains from public evidence. Record OS, version/build, source SHA, CloudKit environment, exact action order, result, and known limitation.

## Audit environment limitations

The initial 2026-11-18 audit could list targets but could not certify full builds/tests. Icon export failed; diagnostic compilation encountered sandbox-denied SwiftUI compiler plugins; CoreSimulator reported a version mismatch. Those failures must not be reported as passing tests or assumed to be source defects. Re-run clean CI and signed device acceptance on the final integrated changes. See [issue 006](issues/006-build-and-verification.md).
