# ADR 0001: one Apple monorepo, two application targets

Date: 2026-11-18. Status: accepted for the 1.0 candidate.

## Context

Monk has three Apple product surfaces with two enforcement implementations. iPhone and iPad use the same Apple APIs, entitlements, extensions, and SwiftUI application. Mac needs application supervision and browser automation. All share a small focus contract in a private CloudKit container. The initial audit found reliability and delivery gaps rather than a need for three repositories or a new backend.

## Decision

Keep `gabebere/monk` as the source of truth. Maintain the existing `Monk` universal phone/tablet target, the `MonkMac` target, mobile extensions, shared source, and tests. Platform directories own UI and enforcement. `Shared/` owns portable models, configuration, compatibility, and sync policy. Do not move files solely to create a corporate-looking directory tree; a physical move must improve a dependency boundary and preserve target membership.

Use one Apple semantic version (`1.0.0`) and source tag (`v1.0.0`), one shared mobile build number including extensions, and an independently incremented Mac build number. The manifest tracks phone, tablet, and Mac readiness separately. A patch can rebuild only the affected artifact while preserving a clear source tag and compatible contract.

Use short-lived branches, pull requests, required automated checks, and manual release workflows. Do not add a permanent `develop` branch, per-platform forks, a developer-operated database, or automatic publication as part of this reorganization. Keep Windows in the monorepo as an explicitly experimental component with separate release scope.

## Consequences

Cross-platform contract changes can be reviewed and tested atomically. Phone/tablet cannot silently drift into separate product versions. Mac delivery remains independently operable. A shared tag does not guarantee simultaneous store availability: release notes and the manifest must record the actual artifact/build availability. Shared-model changes require both Apple builds and compatibility checks. Apple account resources, schema promotion, and distribution approvals remain external release gates.

## Revisit triggers

Revisit only if phone/tablet have materially different entitlement or lifecycle requirements, teams need independent permissions or release cadence, shared source boundaries become unmaintainable, or Windows receives an explicit product decision to join the supported sync system.
