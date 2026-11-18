# 006 — Establish trustworthy build and acceptance evidence

Priority: P1 release gate. Status: unresolved environment/device gate; code checks do not replace signed release validation.

## Audit evidence

On 2026-11-18 the audit could list Xcode targets and schemes using Xcode 27.2. Unsigned Release builds were attempted for generic macOS and iOS devices. Both failed in icon export for `Monk/AppIcon.icon`. Diagnostic builds excluding the icon progressed to Swift compilation but failed when SwiftUI compiler plugins could not launch: `sandbox-exec: sandbox_apply: Operation not permitted` and malformed macro-plugin responses. Mac tests were blocked by the same compilation problem. Xcode also reported a CoreSimulator framework/runtime version mismatch.

These observations do not establish that Monk source is broken on a correctly provisioned Mac. They also do not establish successful builds, passing tests, valid signatures, installability, or working enforcement. Do not fix this by removing required capabilities, disabling system security, deleting user selections, or silently replacing the actual release artifact with a diagnostic build.

## Required verification layers

1. Static checks: centralized version/build values, target membership, matching bundle/container/group identifiers, valid scripts/workflows, release manifest, and documentation links.
2. Clean hosted or local Xcode builds: mobile simulator plus Mac app/tests; record toolchain, destination, commit, and results.
3. Signed artifacts: mobile device archive/export and Mac Developer ID export; inspect entitlements and embedded profiles.
4. Real-device acceptance: Screen Time, extensions, Siri, browser automation, offline replay, account isolation, and three-platform sync.
5. Fresh install and upgrade: Gatekeeper/TestFlight installation, permission flow, launch at login, preservation of local state, and no early-end regression.

## Compatibility and triage

Use the declared minimum runtime separately from the minimum build SDK. Optional 26.4 data-access APIs must remain guarded so supported older runtimes use the token picker. Test phone and tablet layouts independently. Classify failures as source/compiler, assets/toolchain, signing/provisioning, environment permissions, or runtime behavior. Keep diagnostics and exact reproductions; do not label a blocked run as passed.

## Closure criteria

A release approver has recorded passing CI for the final commit, signed archive/export evidence, fresh phone/tablet/Mac acceptance, upgrade tests, and Production CloudKit sync. Unresolved platform limitations appear in the manifest and release notes. Results for an earlier commit must be rerun after relevant source or build changes.
