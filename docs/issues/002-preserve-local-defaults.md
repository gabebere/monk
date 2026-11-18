# 002 — Preserve local allowlists when remote apps cannot be resolved

Priority: P1. Status: code remediation implemented in the 1.0 candidate; final regression/device gates remain open.

## Problem and evidence

The original `fetchDefaultAccessConfiguration()` in `Monk/Services/CrossDeviceFocusService.swift` constructed a new `FamilyActivitySelection` from remotely requested applications and wrote it over the saved local selection. It marked selection configuration complete even if `compactMap(resolvedApplicationToken)` resolved nothing. `mergedPortableApplications()` could publish an empty portable list when a device had valid local tokens but no installed-app data access. These are different states: “no allowed apps,” “unknown identity of local apps,” and “requested app unavailable here.”

## Concrete failure scenario

An iPhone has locally selected Phone and Maps as always allowed. The Mac publishes default blocking with one app that the phone cannot resolve. The phone replaces its saved selection with an empty set and re-enforces default blocking. The existing local exceptions disappear. A non-EU phone can also publish an empty portable list and cause another peer to interpret missing identity data as an intentional empty allowlist.

## Required behavior

Preserve local token selections when remote metadata is unavailable or any requested equivalent is unresolved. Remote portable requests are resolved separately and merged according to explicit default-access semantics. A fully authoritative, completely resolved remote list may replace the prior selection; an explicitly authoritative empty list is an intentional clear. An unresolved app, an unavailable catalog, or an absent optional field must never mean “delete local choices.” Preserve unresolved requests for later mapping. An explicitly intended removal must have a defined, testable representation and must not be inferred from a lossy conversion. Default-blocking enablement and the contents of its local allowlist must be handled independently.

Changes during an active focus must preserve the binding commitment. A remote defaults update must not accidentally erase session selections or silently weaken an active session's policy. The app should disclose unresolved requests instead of reporting a misleading fully synchronized state.

## Compatibility and migration

Keep legacy App Group selection keys readable. Do not reset user defaults, clear the App Group, or require reinstallation. Legacy cloud records without new metadata must follow conservative preservation rules. Preserve tokens even if their portable name is unavailable. Document any explicit behavior for users who later remove a local exception; never use a server reset as a migration step.

## Candidate remediation

`DefaultAccessSyncState` now carries `applicationsAreAuthoritative` and a testable `resolvedSelection` rule. Incomplete matches preserve local choices and merge available equivalents; unavailable metadata leaves local choices intact. Fully resolved authoritative lists replace the prior portable default choice, with explicit true-plus-empty representing a clear. Mobile publishing marks unknown nonempty local selections nonauthoritative. Explicit local mappings can later resolve pending requests. Both platform services use the shared default ordering policy rather than interpreting absent identities as proof that every app should disappear.

## Acceptance evidence

Regression checks must cover: nonempty local selection plus zero remote matches; partial matches; complete matches; empty remote identities due to unavailable catalog; default blocking on/off; an active session; and repeated delivery of the same cloud record. On a real phone and tablet, upgrade from a saved selection and verify the exceptions survive a Mac defaults update. Verify no tokens leave the device.
