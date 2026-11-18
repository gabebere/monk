# Monk 1.0 audit issue register

Audit date: 2026-11-18. These reports describe the pre-remediation code and preserve why the changes are necessary. Source paths are evidence locations, not immutable line numbers. Status is updated against the final working tree; real-device and external-service completion always require recorded evidence.

| ID | Problem | Priority | Completion boundary |
| --- | --- | --- | --- |
| [001](001-worldwide-app-selection.md) | Distributed mobile app discovery is region-limited | P1 | Worldwide token fallback and explicit local mapping; regional device checks |
| [002](002-preserve-local-defaults.md) | Remote defaults can erase local allowlists | P1 | Preserve local selections across unresolved/empty remote updates; regression tests |
| [003](003-reliable-focus-sync.md) | Failed writes, competing sessions, stale ends, and account changes | P1 | Durable retry and explicit merge policy; offline/account/device checks |
| [004](004-device-catalogs-and-identity.md) | Per-platform catalog overwrites and name collisions | P1 | Device-scoped records, compatible reads, collision-safe matching |
| [005](005-repeatable-distribution.md) | Manual release pipeline and unverified production resources | P1 | Repeatable signed artifacts plus external approval/schema evidence |
| [006](006-build-and-verification.md) | Builds and tests could not be certified in the audit environment | P1 release gate | Clean CI, signed device builds, and fresh-device acceptance |

P1 means a release-blocking reliability or delivery issue; it does not imply data exfiltration or an exploitable vulnerability. Privacy and enforcement reports follow [SECURITY.md](../../SECURITY.md).

The reports intentionally distinguish a code remediation from validation and distribution. An implemented change does not close a device acceptance gate or imply that a CloudKit schema has been deployed.
