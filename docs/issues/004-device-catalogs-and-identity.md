# 004 — Device-scoped catalogs and unambiguous application identity

Priority: P1. Status: model remediation implemented with 14 passing focused identity/catalog tests; production-schema and multiple-device gates remain open.

## Problem and evidence

`Shared/CrossDeviceApplication.swift` originally declared three fixed catalog IDs: `application-catalog-macOS`, `application-catalog-iPhone`, and `application-catalog-iPad`. Mac and mobile publish paths wrote those records directly. Two Macs under one Apple Account therefore replaced each other's app inventory. Mobile peers could display an app from whichever Mac wrote last rather than a coherent union.

`CrossDeviceApplication.stableID` originally preferred a normalized display name even when a bundle identifier existed. Different applications with the same name could collapse during deduplication or match the wrong local app. Names also vary by locale and product branding. Cross-platform variants can legitimately have different bundle identifiers, so using only exact identifiers is insufficient without a controlled equivalence/mapping strategy.

## Required behavior

Catalog records must have stable installation-local device identity, platform metadata, schema version, and update timestamp. Separate devices must write separate records. Merge catalog entries without erasing another device's inventory, keep device-local paths and Screen Time tokens out of CloudKit, and avoid exposing hardware identifiers or personal device names unnecessarily. Only publish the inventory that authorization legitimately provides; no new backend or public catalog.

Use exact bundle identity first, explicit known/locally chosen equivalence where available, and only an unambiguous compatibility fallback. A name collision must remain unresolved rather than granting access to an arbitrary first result. Preserve legacy portable IDs during migration where needed, without merging distinct bundle IDs merely because names match.

## Compatibility and migration

Support additive fields and legacy catalog reads during the transition. Device-scoped catalog rollout requires its actual CloudKit record fields and indexes in Production. Define how stale catalogs and reinstalled devices are treated; a random installation UUID is not permanent hardware identity. Mixed-version legacy writers must not erase device-scoped data. Compatibility is asymmetric: 1.0 reads legacy records, but old clients do not discover new per-installation records and may not understand new bundle-based identities. Update all participating devices together for 1.0 acceptance; old-writer concurrency is not certified. A database reset is not an acceptable migration.

## Candidate remediation

`Shared/CrossDeviceApplicationCatalog.swift` stores a random installation UUID, writes a separate catalog record per installation, pages private catalog queries, decodes legacy fixed records, and merges by bundle-aware identity. Catalogs older than 90 days are ignored during reads; legacy undated records remain a compatibility source. Modern catalogs take precedence over legacy snapshots for the same platform. Existing parallel array fields remain the wire format, with strict alignment validation and a 500-app bound.

New identities use bundle-first identity and reviewed cross-platform aliases; conflicting known bundles never match merely by name. Name-only compatibility matching requires an unambiguous candidate. Fourteen focused XCTest cases passed for identity, legacy decoding, malformed arrays, freshness, and merge behavior. No live multiple-device or Production query acceptance is implied.

## Acceptance evidence

Tests cover two catalogs of one platform, duplicate entries across devices, two apps sharing a display name, exact identifier precedence, cross-platform aliases, legacy ID decoding, and deterministic merge order. Real-device validation uses two Macs or two iPhones on one test account and confirms both catalogs survive repeated refreshes. Verify records remain private and contain no raw tokens, filesystem paths, serial numbers, or private device names. Record stale-catalog behavior as a known limitation if retention cleanup is deferred.
