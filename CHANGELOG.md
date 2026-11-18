# Changelog

## 1.0.0 — Unreleased

This candidate establishes the Apple 1.0 source organization and release process. It has not been tagged, published, or certified for distribution by this document.

### Product and organization

- Defined Monk for iPhone, iPad, and Mac as three supported product surfaces with one universal mobile target and a separate native Mac target.
- Added product/platform contracts, architecture/data documentation, audit issue reports, verification matrices, and operational runbooks.
- Added ownership and pull-request/issue templates, declarative GitHub governance configuration, and explicit live-settings audit/apply tooling.

### Reliability and selection

- Added shared conflict policy and durable portable pending sync state, conditional CloudKit writes, retry/backoff, and account-change handling.
- Preserved local mobile selections when remote app identities are unavailable or incomplete.
- Kept Apple's native token picker available worldwide and added explicit local equivalents for unresolved remote apps.
- Introduced installation-scoped catalogs and bundle-first portable app identities with conservative compatibility matching.

### Delivery

- Centralized Apple marketing version and platform build numbers.
- Added explicit shared Mac test/archive scheme, unsigned Apple CI, repository/export validators, and a release readiness manifest.
- Added an isolated core XCTest entry point that exercises the real policy/service sources without launching Monk or compiling UI assets.
- Added local signed archive/export tooling and Mac notarization/stapling/DMG packaging; artifact creation is separate from upload/publication.

### Open release gates

- Final integrated clean CI and signed archive/export verification.
- Apple Family Controls distribution approval and matching profiles for the app/extensions.
- Additive CloudKit Production schema/index deployment and Production sync testing.
- Non-EU distributed mobile selection/mapping, offline/conflict/account isolation, upgrade, and fresh-device acceptance.
- Accepted notarization/Gatekeeper checks for the actual Mac artifact.
- Live GitHub protection/settings application, subject to account permissions and passing CI.

Windows remains experimental and outside the Apple 1.0 release promise. Automatic mobile installed-app data access remains subject to Apple's OS, authorization, and EU customer eligibility restrictions.
