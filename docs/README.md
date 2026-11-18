# Monk engineering handbook

This is the entry point for building, operating, and releasing Monk. Version **1.0.0 is an unreleased candidate** until the release gates have recorded evidence. Source code, configuration, signing approvals, and a shipped product are separate states.

## Product and ownership

- [Monk 1.0 product contract](PRODUCT_1.0.md): scope, supported platforms, behavior, and release criteria.
- [iPhone](platforms/IPHONE.md), [iPad](platforms/IPAD.md), and [Mac](platforms/MAC.md): platform responsibilities and acceptance checks.
- [Architecture](ARCHITECTURE.md) and [data contract](DATA_CONTRACT.md): component boundaries, private CloudKit data, local state, and compatibility.
- [Architecture decision: one Apple monorepo](decisions/0001-apple-monorepo.md): why phone and tablet remain one universal application.

## Development and delivery

- [Setup](SETUP.md): developer identifiers, signing, local builds, and device requirements.
- [GitHub operating model](GITHUB.md): branches, reviews, ownership, checks, releases, and repository settings.
- [Release engineering](RELEASES.md): versioning and the two Apple distribution paths.
- [Release checklist](runbooks/RELEASE_CHECKLIST.md): evidence required for each platform.
- [CloudKit operations](runbooks/CLOUDKIT.md): development/production schema and account-isolation checks.
- [Sync recovery](runbooks/SYNC_RECOVERY.md): diagnose pending writes, unresolved apps, and divergent sessions.
- [Verification matrix](VERIFICATION.md): automated checks and real-device scenarios.

## Audit and follow-up

The [issue register](issues/README.md) preserves the original failure scenarios, remediation decisions, compatibility requirements, and completion criteria. [CHANGELOG.md](../CHANGELOG.md) describes changes in the unreleased candidate. The machine-readable release manifest is [release/1.0.0.json](../release/1.0.0.json).

Windows remains experimental and has its own [architecture](../Windows/ARCHITECTURE.md) and [roadmap](../Windows/ROADMAP.md). It is outside the Apple 1.0 release gate.
