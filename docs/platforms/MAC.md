# Monk for Mac (MonkOS) 1.0

Status: unreleased candidate. Target/scheme: `MonkMac`. Product: `MonkOS.app`. Bundle: `$(MONK_MAC_BUNDLE_IDENTIFIER)` (upstream `com.gbr.Monk.mac`). Minimum runtime: macOS 14. Distribution: Developer ID signed, hardened-runtime, notarized direct download.

## Responsibility

`MonkMacEnvironment` composes the focus store, installed-app catalog, local application guardian, browser guardian, sync service, hotkey/panel controllers, and launch-at-login controller. Mac owns local bundle paths and process/browser supervision. Portable app descriptions and focus intent participate in the same user's private CloudKit contract.

The full enforcement build is intentionally outside the Mac App Store. Its direct distribution artifact must preserve CloudKit and Apple Events entitlements and include the required provisioning support for CloudKit. A Debug app copied into `~/Applications` by the developer script is not the release artifact.

## Operational behavior

`Option` + `Space` opens the command panel. A running focus/default-blocking policy can refuse ordinary app termination. The development launcher respects that refusal; release and maintenance procedures must not introduce an early-stop command. Browser website enforcement depends on supported browser automation settings and macOS permissions. Desktop enforcement is a behavioral boundary in the user's session; an administrator can ultimately stop/remove the software.

Local app selection uses installed bundle identities. Name-only ambiguity must remain unresolved. Multiple Macs can publish separate catalogs without overwriting one another. The local focus restores across relaunch, while cloud reconciliation must not blindly republish stale state over a newer commitment.

## Release acceptance

- [ ] Signed archive/export has the expected Developer ID identity, iCloud provisioning, entitlements, version/build, and CPU architectures.
- [ ] Notarization and stapling succeed; Gatekeeper accepts the downloaded artifact on a fresh Mac.
- [ ] Installation at a stable application path, first launch, menu bar, command panel, and permissions work.
- [ ] Launch at login is verified after reboot and its approval state is understandable.
- [ ] Supported browser website allowlists and app guardian enforce correctly.
- [ ] Ordinary quit during active focus remains refused; expiry extend/finish works.
- [ ] Two Macs preserve separate catalogs; ambiguous names do not grant an arbitrary app.
- [ ] Offline start/extend/end survives relaunch and converges with phone/tablet after reconnect.
- [ ] Upgrade preserves local state and permissions as expected for the signature/identity.

Use [release engineering](../RELEASES.md) for artifact commands. Download installation and a development launch are separate acceptance cases.
