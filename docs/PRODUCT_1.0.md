# Monk 1.0 product contract

Status: unreleased candidate. Product owner and release approver: the repository owner. A checked-in `1.0.0` version is a release target, not proof of a published build.

## Product behavior

Monk is a minimal allowlist focus tool. A person chooses an intention, duration, allowed apps, and allowed websites. Every other app or website is unavailable within the platform's enforcement boundary. An active commitment cannot be ended early. At expiry, the person chooses to extend or finish. Optional default blocking keeps all apps except explicitly chosen exceptions unavailable between sessions.

One person can coordinate a commitment across their Apple devices using the same Apple Account and CloudKit environment. Local enforcement continues when the network is unavailable. Cross-device delivery is eventually consistent; mobile background execution and silent push delivery are controlled by the OS and are not an instantaneous remote-control guarantee.

## Release units

| Product surface | Version | Xcode target | Distribution artifact | Minimum runtime |
| --- | --- | --- | --- | --- |
| Monk for iPhone | 1.0.0 | `Monk` | Universal iOS/iPadOS application | iOS 18.5 |
| Monk for iPad | 1.0.0 | `Monk` | Same universal application and mobile build number | iPadOS 18.5 |
| Monk for Mac (MonkOS) | 1.0.0 | `MonkMac` | Developer ID signed, notarized direct download | macOS 14 |

Phone and tablet have separate acceptance evidence and release notes when behavior differs, while sharing one App Store listing and binary. Splitting their targets would duplicate signing, extensions, and schema work without a current product requirement. Mac has its own build number because it is a separate artifact. The Apple source release uses a single semantic version and tag.

Installed-app data access is optional and requires iOS/iPadOS 26.4 or newer plus Apple's authorization and regional eligibility. It is not a requirement for local token-based selection. [Issue 001](issues/001-worldwide-app-selection.md) explains the distributed-build limitation.

## Privacy and infrastructure

- No Monk account or developer-operated sync server.
- Focus metadata and portable app descriptions use the current user's private CloudKit database.
- Screen Time tokens, local mappings, local bundle paths, and enforcement grants stay on their originating device.
- No analytics, advertising, subscription system, productivity integrations, or new onboarding system without an explicit product decision.
- Signing certificates, provisioning profiles, notarization credentials, and private database exports never enter source control.

## 1.0 acceptance

All three platform checklists must be complete before calling the coordinated Apple release generally available. Local builds, App Store/TestFlight approval, CloudKit Production deployment, and fresh-device installation each require their own evidence. Known limitations must be in release notes.

The release must demonstrate offline recovery, a start/extend/finish round trip across phone/tablet/Mac, ambiguous and unavailable app matching, two devices of the same platform, account switching without cross-account replay, upgrade preservation of local selections, and permission recovery. See [verification](VERIFICATION.md).

## Deliberate limits

Desktop enforcement runs in a user's session; an administrator can stop or remove the app. Mobile enforcement depends on Apple's Screen Time authorization. A person must authorize each device and select any local equivalents that cannot be resolved automatically. Windows is experimental and local-only; it is not part of the Apple 1.0 product promise.
