# Project Progress

This file summarizes the current codebase state so other agents can ramp quickly.

## Architecture snapshot
- SwiftUI iOS app using SwiftData models `FocusSession`, `Project`, `Preferences`; `ModelContainer` is configured for CloudKit private DB `iCloud.com.gbr.Monk` with a local fallback if CloudKit init fails.
- Core services: `FocusManager` (start/stop, today total recalculation, short-session purge, per-project hard block activation), `InsightsAnalyzer` (aggregations for goal/insight cards), `EntitlementSyncService` (iCloud KVS flag), `RevenueCatService` (offerings/purchases/entitlement listener), `CalendarIntegration` (EventKit write/backfill), `AnalyticsService` (PostHog client gated by `telemetry_enabled` flag but defaulted to true), `AuthManager` (Apple/Google sign-in state).
- UI shell: `ContentView` gates auth/onboarding, drives TabView (Home, Insights, History, Settings), paywall gating for the start CTA via RevenueCat entitlement plus entitlement-sync flag, onboarding paywall flow, demo data seeding.
- Targets/extensions: Hard block shield UI extension with custom branding; DeviceActivity report stub; WidgetKit/ActivityKit target (`MonkLiveActivities`) for focus/live goal surfaces; app group storage for hard-block state.

## Feature status
- Focus flow: Start/stop sessions, optional project selection sheet, per-project hard block activation, optional discard of sessions under 2 minutes, location capture on stop, calendar write/backfill when enabled, today total updates each tick. Live Activity update hooks exist but focus score snapshot is currently `nil`.
- Projects: Create/edit with weekly goal cap (112h aggregate), per-project hard block selection, delete project cleanup; goal progress surfaced on Home; detail view supports rename, goals, blocking.
- Insights: Goal summary + project goal bar fed by `InsightsAnalyzer`; temporal charts, streaks, and mood trends are not implemented yet.
- Settings: Account sign-in/out, telemetry toggle (defaults on), discard-short toggle, calendar selection with backfill/purge helpers, location permission helper, feedback via UserJot web view with signed token, debug tools (onboarding preview, analytics test event, RevenueCat reset).
- Auth/onboarding: Auth gateway plus onboarding story; setup checklist for login/Screen Time/calendar/location shown after entitlement or onboarding paywall dismissal.
- Monetization: RevenueCat SDK configured with live public key (`appl_MdQJjbrjYFxzEaabiQbrRLrmDZc`); Home CTA shows RevenueCat paywall unless `isPro` or entitlement-sync flag is true; debug purchase reset clears entitlement KVS and logs in a new RC user.
- Sync: SwiftData configured for CloudKit sync; entitlement sync via `NSUbiquitousKeyValueStore`; no live session mirroring service present.
- RevenueCat specifics (from RC guide): entitlement id `Monk Subscription`; gating uses `customerInfo.entitlements`; paywall is RevenueCatUI (requires a dashboard paywall attached to the default offering). Current builds always use the live iOS key; Test Store key is not used. Restore/manage subscriptions hooks exist via `restore()` and `showManageSubscriptions()`.

## Gaps / risks to track
- Mood capture and satisfaction-driven insights are unused: `FocusSession` has no mood field and Mood UI is not wired to data.
- Telemetry defaults to enabled despite the spec calling for opt-in; PostHog keys are embedded in `AnalyticsService`.
- Live session sync docs mention `LiveSessionSyncService`, but no such service exists in code.
- Insights UI lacks weekly/day charts, streaks, or mood trends promised in spec/docs.
- No tests in the repo (`MonkTests`/`MonkUITests` absent).

## Suggested next steps
- Decide whether to add mood storage + charts or strip mood copy.
- Align telemetry default and analytics gating with the privacy stance.
- Clarify/remove live session mirroring references or implement the service.
- Expand insights UI to meet spec (daily/weekly charts, streaks, mood trends).
- Add unit/UI tests for FocusManager, aggregation, and navigation basics.
