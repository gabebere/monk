# Monk for iPad 1.0

Status: unreleased candidate. Target/scheme: `Monk`. App bundle: `$(MONK_BUNDLE_IDENTIFIER)` (upstream `com.gbr.Monk`). Minimum runtime: iPadOS 18.5. Distribution: the same universal application, App Store listing, version, and mobile build number as iPhone.

## Responsibility

iPad shares the mobile service, extensions, entitlements, and portable contract with iPhone. It stores its own local Screen Time selections and mappings. A token selected on a phone is never assumed to identify the same app on a tablet. Device-scoped catalog metadata identifies iPadOS separately when optional installed-app data access is available.

A separate tablet target is not required to make the product professionally maintained. Tablet-specific layout and lifecycle acceptance is required even though the source and artifact are shared.

## Tablet acceptance

Complete the [iPhone behavior checks](IPHONE.md) on iPad as well, plus:

- [ ] Portrait and landscape composer, active focus, settings, and system picker are usable.
- [ ] Narrow split view and resizable window widths retain readable controls and reachable actions.
- [ ] Keyboard focus, dismissal, and scrolling do not obscure duration or app-selection controls.
- [ ] Start on iPad, extend on Mac/phone, and finish after expiry; verify equivalent local enforcement.
- [ ] A mobile app installed only on the tablet is represented without erasing another device's catalog.
- [ ] Missing local equivalents stay visible and can be explicitly mapped with local tokens.
- [ ] A phone and tablet on the same account preserve different local always-allowed selections.
- [ ] Background suspension and relaunch retain active enforcement and pending state.

Automatic installed-app data access has the same 26.4+, authorization, and EU customer restrictions as iPhone. Older supported releases and other regions use token selection and explicit local mapping. Release notes must describe actual tablet limitations rather than implying every installed app can be named automatically.
