# TODO

## Doc/code discrepancies to resolve
- Update `KNOWN_ISSUES_LIVE_SYNC.md` and `INTERDEVICE_CONNECTIVITY.md`: code has no `LiveSessionSyncService`; only CloudKit sync and entitlement KVS exist.
- Refresh `SPEC.md` (data model, privacy) and any references to mood/soft-block fields: `FocusSession` has no `moodScore`; `Preferences`/`Project` soft-block fields are absent; current models include calendar/location data.
- Align privacy copy with implementation: spec says telemetry opt-in/off, but `SettingsView` defaults `telemetry_enabled` to true and `Analytics.configure()` boots PostHog immediately.
- UserJot: native SDK identify still prompts login; need backend-signed tokens (if supported) or switch to web widget with signature to achieve one-tap auth.
- RevenueCat launch checklist:
  - Dashboard: attach paywall to the default offering; packages `$rc_monthly` → `monk_monthly`, `$rc_annual` → `monk_annually`; entitlement id `Monk Subscription`.
  - StoreKit: ensure products are approved in App Store Connect (no “Empty Product titles” warnings).
  - Keys: keep live iOS public key in Release; do not ship with Test Store key; optionally set `.debug` log level for Debug only.
  - QA: verify paywall renders (not nil), purchase/restore/manage-subscriptions flows on device/sandbox; keep gating on `customerInfo.entitlements`.

## Product gaps before App Store
- Mood logging: either add a mood field to `FocusSession`, surface the slider on stop/edit, and pipe into `InsightsAnalyzer`, or remove mood UI/copy from insights.
- Insights completeness: add daily/weekly charts, streaks, and mood trends promised in the spec; current Insights tab only shows goal summary and project goal bar.
- Sync story: confirm CloudKit entitlements/config work; if live session mirroring is desired, build the KVS-based service (start/stop propagation + UI prompts) or scrub the feature from docs.
- Telemetry opt-in: default telemetry off, gate analytics init/events on consent, and verify no network calls before the toggle is enabled.
- RevenueCat readiness: ensure offering/paywall is configured in the dashboard; consider `.debug` log level for debug builds and verify restore/manage flows.
- Testing: add unit/UI tests (FocusManager start/stop + midnight, Insights aggregation) because the repo currently has none.
- Settings UX: clarify calendar behavior (“always writes”) and expose manual resync/purge buttons if needed for users.
- Live Activities: `LiveActivityManager` uses a `FocusScoreSnapshot?` placeholder; ensure WidgetKit target builds, entitlements are configured, and lock screen layouts are validated on device.

## Compliance/cleanup
- Audit hardcoded keys (RevenueCat, PostHog, UserJot) and ensure intended for release; move secrets server-side where applicable.
- Confirm CloudKit/App Group/Screen Time entitlements are enabled across app and extensions before submission.

## Archived notes from removed docs
- Live session sync (iCloud KVS, now absent in code): planned `LiveSessionSyncService` would publish start/stop with session/project IDs and selection data, mirror sessions on other devices if fresh (<180s), apply hard block, and prompt via local notification; known issues included mirrored sessions not appearing and notifications not firing reliably.
- Interdevice connectivity: intended layers were SwiftData+CloudKit for persistence, KVS for entitlement flag, and KVS for live session mirroring (not implemented); no backend/push/P2P.
- UserJot integration: auto-login via native SDK not achievable without signed tokens; web flow needs backend HMAC/JWT signing of user ID and a WKWebView-embedded widget if native token support is missing.
