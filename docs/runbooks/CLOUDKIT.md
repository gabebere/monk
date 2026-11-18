# CloudKit schema and operations

Monk uses the current user's private CloudKit database in the configured container. There is no custom database server to provision. The [data contract](../DATA_CONTRACT.md) is the schema reference; this runbook supplies operational checks.

## Development setup

1. Create/verify the iCloud container owned by the developer team and associate both app identifiers.
2. Run signed development builds under the same test Apple Account and Development environment.
3. Exercise focus start/extend/end, default blocking, catalog publication, query paging, and mobile notification subscription so all required fields/index needs are observable.
4. Inspect schema and operation errors in CloudKit Console. Review records only under authorized test accounts; do not export personal records to source control.

The configured container ID must agree between Info.plist expansion, signed entitlements, provisioning profiles, and both platform apps. App Group agreement is a separate local mobile-extension requirement.

## Candidate schema changes

The 1.0 candidate retains existing focus/default/catalog record types and singleton names. It adds `MonkDefaultAccess.applicationsAreAuthoritative` and catalog `deviceID`/`schemaVersion`, and publishes device-scoped catalog record IDs. Verify the catalog query can enumerate every page and the mobile focus subscription can be saved and delivered. A successful fixed-ID fetch does not validate query indexes.

Do not remove fields/types already used by distributed clients. Inspect the code and schema together before promotion; never assume a development run promoted the schema automatically.

## Production promotion

1. Review pending schema changes and indexes in CloudKit Console using the correct team/container.
2. Deploy additive schema changes to Production before shipping dependent clients.
3. Record the deployment date, reviewed schema changes, responsible maintainer, and source SHA.
4. Install release-signed Production builds on phone, tablet, and Mac using a separate test account.
5. Verify record writes, catalog queries, subscriptions/foreground refresh, conflict handling, offline replay, and account isolation.

Apple's [schema deployment documentation](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema) explains that promotion copies schema, not records. Development and Production are distinct datasets. A development Mac and a TestFlight phone may point at different environments even when their container names match.

## Diagnose failures

| Symptom | Check |
| --- | --- |
| Device local focus works, peers never update | Account/environment/container agreement; pending write status; network; CloudKit errors |
| Legacy catalog fetch works, new device app lists absent | Production fields and actual catalog-query index; query error and pagination |
| All phone choices disappear after defaults update | Selection-preservation regression; authority flag and mapping state; do not clear user defaults |
| Notification missing | Final push entitlements, subscription creation, OS delivery restrictions; foreground refresh behavior |
| `serverRecordChanged` | Conditional retry/merge behavior; do not overwrite unconditionally |
| Not authenticated or account changed | Pause cloud operations and verify current account; do not replay old-account data |

## Safe recovery

Preserve local focus and selections while diagnosing. Do not reset Production, delete the App Group, remove signing capabilities, or ask a user to uninstall during a binding commitment as a routine fix. Stale catalogs are currently filtered by age during reads; that is not server deletion. Reinstallation may create a new device UUID, so any future cleanup must consider active installations and legacy compatibility.

Escalate a suspected privacy/account-isolation issue through [SECURITY.md](../../SECURITY.md). Public issue evidence should contain sanitized error codes, build/OS/environment, and timestamps—not tokens or private record payloads.
