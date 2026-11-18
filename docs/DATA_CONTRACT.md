# Apple data and sync contract

Contract scope: Monk 1.0 candidate, configured CloudKit container `$(MONK_CLOUDKIT_CONTAINER)` (upstream `iCloud.com.gbr.Monk`), **current user's private database**. This document describes the repository contract. It is not an export of the live database and does not certify Production schema deployment.

## Sources of truth

- `Shared/CrossDeviceApplication.swift`: record constants and portable application identity.
- `Shared/CrossDeviceApplicationCatalog.swift`: catalog schema, device identity, paging and merge behavior.
- `Shared/FocusSyncState.swift`: portable focus/default state, conflict policy, pending-journal model.
- `Shared/CloudKitSyncOutbox.swift`: wire encoding, conditional writes, durable retry and account binding.
- `Monk/Shared/CrossDeviceFocusState.swift`: local mobile active state, including local selection data; never upload this whole type.
- Platform services: authorization, lifecycle, token/descriptor resolution, and applying the shared result.

## Cloud record families

| Record type | Record name | Purpose |
| --- | --- | --- |
| `MonkFocusCommitment` | `current-focus-commitment` | Current portable commitment or its end marker |
| `MonkDefaultAccess` | `current-default-access` | Shared default-blocking preference and portable app requests |
| `MonkApplicationCatalog` | `application-catalog-macOS-<installation-uuid>`, `application-catalog-iPhone-<installation-uuid>`, `application-catalog-iPad-<installation-uuid>` | Separate authorized catalog per installation |
| `MonkApplicationCatalog` | Legacy names without the UUID suffix | Compatibility reads for older clients |

No record family is a user/account table or session archive. A CloudKit private database already supplies the Apple Account boundary. There is no requirement to duplicate an email address, hardware ID, or private user identity into records.

## Focus fields

| Field | CloudKit value | Meaning |
| --- | --- | --- |
| `sessionID` | String UUID | Stable commitment identity through extensions |
| `intention` | String | Person's chosen focus description |
| `startedAt`, `endsAt` | Date | Commitment interval; an extension keeps the session ID and moves the end later |
| `allowedDomains` | String list | Portable website allowlist |
| `allowedApplicationIDs` | String list | Portable app identities |
| `allowedApplicationNames` | String list | Corresponding display metadata |
| `allowedApplicationBundleIdentifiers` | String list | Corresponding bundle identifiers; empty string means unknown |
| `sourcePlatform` | String | Source platform metadata, not a device identity |
| `sessionStatus` | String | `active` or `ended` |

Application lists are a legacy parallel-array wire format. Index alignment must be preserved. Missing optional fields remain decodable for older records. Invalid session IDs/dates must be rejected rather than applied. Opaque Screen Time tokens and `allowedSelectionData` are not fields in this record.

## Default-access fields

| Field | CloudKit value | Meaning |
| --- | --- | --- |
| `enabled` | Boolean/NSNumber | Whether default blocking is enabled |
| `updatedAt` | Date | Default-access update ordering |
| `applicationIDs`, `applicationNames`, `applicationBundleIdentifiers` | Parallel string lists | Portable requested exceptions |
| `applicationsAreAuthoritative` | Boolean/NSNumber, additive | Whether the source could read the complete portable identities; false must not turn missing names into a clear command |
| `sourcePlatform` | String | Source platform metadata |

The new authority flag uses conservative legacy decoding: an old record with an empty portable list and no flag is nonauthoritative. Only explicit true-plus-empty clears a selection. Platform services also preserve local choices when resolution is unavailable or incomplete. Locally selected tokens and resolved remote equivalents are distinct inputs. Nonauthoritative metadata leaves the local selection unchanged; partial matches union the resolved equivalents into it. When every requested app is resolved, the authoritative remote list replaces the prior selection; an explicitly authoritative empty list clears it. Repeated delivery must not progressively delete local exceptions during incomplete matching. Default-blocking enablement is separate from app-resolution success.

## Catalog fields and retention

| Field | CloudKit value | Meaning |
| --- | --- | --- |
| `schemaVersion` | Integer/NSNumber | Catalog format version; current value 1 |
| `deviceID` | String UUID | Random persisted installation identity |
| `platform` | String | `macOS`, `iOS`, or `iPadOS` |
| `updatedAt` | Date | Catalog freshness |
| `applicationIDs`, `applicationNames`, `applicationBundleIdentifiers` | Parallel string lists | Authorized portable catalog entries, maximum 500 per record |

Catalog reads page through the private record type, with legacy direct-record fallback for older schemas. Modern catalogs replace legacy catalog data for the same platform when merging; one installation does not overwrite another. The merge excludes catalogs older than 90 days; legacy records without dates remain a compatibility source. This is read filtering, not server-side deletion. Reinstallation can create a new UUID, and stale server records require deliberate future cleanup if needed.

Production must support the catalog query as well as new fields. Test the exact query and notification subscription against Production; direct fetches succeeding alone do not prove required indexes are deployed.

## Application identity and mapping

Bundle identity takes precedence where present. Known cross-platform equivalents and explicit on-device mappings can bridge variants with different bundle identifiers. A normalized display name is compatibility metadata; two different known bundle identities must not collapse solely because their names match. Ambiguous matching remains unresolved and should be actionable in the UI.

The mobile user can map a requested remote app to exactly one locally chosen token. That mapping is local-only. Neither the native token nor a serialized `FamilyActivitySelection` is a portable identifier. Mac policies retain optional portable allowed-app metadata separately from locally resolved descriptors, so a mobile-only request is not lost when the Mac restarts or extends the commitment. The catalog's installation UUID is not a hardware identifier and should not be used for tracking.

## Conflict and retry policy

If a device reconnects after a different, longer winning commitment has already finished, its older local commitment may complete only once both deadlines have elapsed and the shared resolver selects that finished winner. A still-active local commitment remains protected from unrelated end markers.

The shared focus resolver is the source of truth. For the same session, a later end date wins; an end marker can apply only after the relevant interval expires, so a delayed end cannot erase an extension. For independent overlapping commitments, the longer deadline wins; deterministic UUID ordering breaks equivalent ties. The complete winning policy wins: app allowlists are not unioned, and the loser's intention/app selection can therefore change when convergence occurs. Non-overlapping commitments prefer the newer session. Applying a result must not shorten an already active local commitment.

Writes first persist portable mutations to a local journal, coalesced by singleton record. Cloud operations verify the iCloud account, fetch current change tags, resolve against current server state, and retry bounded server conflicts. Transient failures use backoff and CloudKit's retry hint. The local journal survives relaunch; polling/foreground opportunities drive later attempts. Account-change notifications invalidate in-flight work and quarantine the existing verified-owner journal until identity is verified again. The same verified account can resume pending work after a transient sign-out; a different verified account discards the old outgoing state. A first-ever offline journal without a verified identity binds to the first account actually verified. Durable per-session account ownership also prevents a previously received/adopted local session from being re-uploaded into another account. Network unavailability must not clear local enforcement.

Default updates compare full-precision timestamps and break ties using a canonical fingerprint containing authority, app metadata, and source. Clock-based ordering and older clients that do not implement the new resolver remain mixed-version risks. Validate device clock changes and upgrades rather than claiming linearizable distributed locking. No background-delivery latency SLA is provided.

## Compatibility and deployment

Legacy restored sessions without durable account provenance remain enforced locally and are quarantined from outgoing sync. A matching session fetched from a verified private database can establish ownership. A newly created offline session already present in the pending journal is distinct from this legacy case and can bind normally on its first verified connection.

All schema changes are additive. Keep existing record types, singleton names, bundle IDs, container ID, and App Group unless an explicit migration is designed. Deploy fields/indexes in Development and then promote the schema to Production before distributing clients that need them. Promotion copies schema, not personal records. Never reset Production or upload a development user's database to migrate schema.

Record exact schema deployment, client builds, and mixed-version results in [release evidence](runbooks/RELEASE_CHECKLIST.md). Compatibility is asymmetric: the 1.0 reader understands legacy catalog records, while old clients cannot discover new installation-scoped records and may not match new bundle-based IDs. Old clients can still write legacy records and do not gain new conflict semantics merely because new fields exist. Update all participating devices together for 1.0 acceptance; do not claim safe mixed-version concurrent writers without separate evidence.
