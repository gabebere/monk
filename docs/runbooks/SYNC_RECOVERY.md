# Diagnose and recover cross-device sync

Start by preserving the active local commitment. A network or account failure does not authorize ending it early. Do not clear preferences, delete the App Group, or reset CloudKit as a first diagnostic step.

## Collect non-sensitive context

Record platform/OS, Monk version/build or source SHA, affected devices, Development/Production environment, whether each uses the same intended Apple Account, network availability, and whether Screen Time/browser permissions are approved. Do not collect account email, raw tokens, private intention/domain text, or full database exports in public issues.

## Local versus cloud behavior

If blocking works locally, inspect whether changes are pending rather than assuming publication succeeded. The outbox is a local Application Support journal containing portable state; it is not a user-facing data export. The queue coalesces focus/default singleton updates and retries on subsequent lifecycle/poll opportunities. iOS suspension can delay retries and silent notifications; opening Monk permits foreground reconciliation.

An account-change notification quarantines the verified-owner outgoing journal until identity is rechecked. The same verified account can resume after a transient sign-out; a verified different account drops the old pending writes. Do not manually copy an old journal into a new account. A current local commitment can remain enforced without being re-uploaded as a new-account record. A first-ever offline unbound mutation binds to the first account actually verified; validate this product behavior in account tests.

## Unresolved applications

A restored legacy session with no recorded account owner may remain local-only until the same session is fetched from a verified account. This protects old focus text from being uploaded to a different account. Finish the commitment normally before starting a new synchronized one; do not edit the journal to bypass quarantine.

A portable requested app and a local token are different representations. On mobile, open the unresolved-app action and choose the intended local equivalent with Apple's picker. That mapping stays local. Installed-app search is optional and cannot be assumed in non-EU customer installations. If names collide, do not choose an arbitrary automatic result. Verify that the mapped app alone becomes available.

A remote update with no resolved equivalents must preserve existing local exceptions. If it does not, collect reproduction context and treat it as a regression in [issue 002](../issues/002-preserve-local-defaults.md), not as a reason to reset the device.

## Independent sessions and delayed updates

The shared policy resolves overlapping independent commitments using the later deadline and a deterministic tie break; the whole winning policy is retained, without unioning app allowlists. Same-session extensions take precedence over an earlier end. Before retrying or repairing state, compare the session interval and whether the local commitment is still active. Do not add an administrative “force finish” action to resolve disagreement.

After reconnecting, allow foreground reconciliation on each device and verify convergence. If it does not converge, record sanitized timing/order information and operation errors for [issue 003](../issues/003-reliable-focus-sync.md).

## Operational decision

- Local enforcement broken: check authorization, App Group/configuration, and native guardian behavior on that platform.
- Only cloud delivery broken: check account/environment agreement, pending status, schema/query/subscription errors, then retry lifecycle opportunities.
- Only an app is missing: inspect local mapping/catalog eligibility and identity ambiguity.
- Only an installed release fails: compare final signed entitlements/profiles and Production schema against development configuration.

Keep diagnostics separate from release claims. A successful manual recovery does not close the offline, mixed-version, or account-isolation acceptance tests.
