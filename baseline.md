# Monk Baseline Blocker + Shortcut Unlock Spec

## Goal
Add a global “Baseline Mode” that blocks apps by default and makes app access intentional via a typing-based unlock flow driven primarily by a Shortcut. Unlocks are time-limited, stack, and re-lock strictly even if Monk never opens again.

This spec must work with real app names (best effort), without aliases.

## Definitions
- Baseline Mode: global behavior independent of focus sessions.
- Always Allowed: apps that are never blocked, even if user forgets.
- Never Block Categories: Screen Time categories that are never blocked while Baseline Mode is ON.
- Unlockable Apps: apps the user chooses that can be unlocked via typing.
- Temporary Unlock: time-limited allow of a single app. Unlocks stack.

## Requirements Summary
1) Baseline Mode is a global toggle in Settings.
2) When Baseline Mode is ON, apps are blocked by default, except Always Allowed apps and Never Block Categories.
3) Users must pick Baseline configuration manually (no default allowlist), but Monk always force-allows Phone, Messages, and emergency access apps.
4) User can select any Screen Time category to be “Never Blocked.”
5) Unlock flow:
   - Primary: run “Monk Unlock” Shortcut.
   - Shortcut prompts typing app name prefix.
   - Auto-resolve when the prefix uniquely matches exactly one unlockable app.
   - Select duration: presets 2, 5, 10 minutes, plus Custom 2 to 60 minutes.
   - Unlock the app for that duration and try to open it automatically (best effort).
   - No “Lock Now” button, no early end.
   - Unlocks stack (multiple apps can be unlocked concurrently).
6) Siri support: “Monk <AppName> <Minutes>” unlocks app for minutes (same constraints and matching).
7) Strict relock: relock enforced even if user never returns to Monk, using a DeviceActivityMonitor extension.
8) Widget behavior:
   - Widget is an entry point.
   - On tap, open Monk deep link monk://quickunlock.
   - Monk immediately attempts to run the Shortcut. If Shortcut is missing, show in-app fallback unlock UI (still typing based).
9) Analytics (local only):
   - unlock count
   - total unlocked time
   - top unlocked apps
   - No intention text, no relapse patterns

## Non-Goals
- No pinned unlocks, no recent unlocks UI.
- No default deny lists with extra friction.
- No manual relock.

## Platform Constraints Acknowledged
- Widgets cannot accept text input. Typing happens in Shortcut or in Monk fallback UI.
- Automatic app opening is best effort only: use known URL schemes or universal links when available; otherwise user opens manually from Home Screen.

## Architecture Overview
Create a new Baseline system that parallels HardBlock:
- ManagedSettingsStore for baseline enforcement: .baselineBlock
- App Group shared state for baseline settings and active temporary unlocks
- DeviceActivityMonitor extension to enforce strict relock on expiry and schedule boundaries
- AppIntents to support Siri and Shortcut calls into Monk

Must not break existing Project Hard Block. Baseline and Project shields stack via separate store names.

## Data Model

### 1) SwiftData: Preferences additions
Modify `Monk/Models/Preferences.swift` to include:

- baselineEnabled: Bool (default false)
- baselineScheduleEnabled: Bool (default false)
- baselineScheduleData: Data? (JSON encoded schedule model)
- baselineAlwaysAllowedSelectionData: Data? (FamilyActivitySelection encoded)
- baselineNeverBlockCategoriesSelectionData: Data? (FamilyActivitySelection encoded, categories only)
- baselineUnlockableAppsSelectionData: Data? (FamilyActivitySelection encoded, applications only)

Notes:
- User must pick manually, but emergency apps are force-allowed regardless of user selection.

### 2) Shared App Group files (group.com.gbr.Monk)
Create a Baseline state store similar to HardBlockStateStore:
- File: baselineState.json
- Holds:
  - baselineEnabled
  - scheduleEnabled + schedule definition
  - selectionData for:
    - alwaysAllowedSelection
    - neverBlockCategorySelection
    - unlockableAppsSelection
  - activeUnlocks: list of { applicationTokenData, expiresAt, durationSeconds, startedAt }

Create a second file for an app name index:
- File: baselineAppIndex.json
- Holds:
  - entries: list of { applicationTokenData, displayName, normalizedName }
- Purpose: prefix matching based on real app names best effort.

Normalization rules:
- lowercase
- trim spaces
- remove punctuation characters . , ! ? : ; ' " ( ) [ ] { } - _ and repeated spaces collapsed
- do not transliterate

Important behavior:
- If displayName cannot be resolved for a token, that app is excluded from unlockable matching and must show a warning in setup UI: “This app name is unavailable to Monk and cannot be unlocked via typing.”

### 3) Analytics
Create SwiftData model `UnlockEvent`:
- id: UUID
- applicationTokenData: Data
- appDisplayName: String
- startedAt: Date
- durationSeconds: Int
- endedAt: Date (computed or stored)
- source: enum { shortcut, siri, inAppFallback }

Compute metrics in Settings:
- unlockCount (last 24h, 7d, 30d)
- totalUnlockedTime (same)
- topUnlockedApps by total time (same)

No intention text stored.

## Baseline Enforcement Rules

### Force-allowed apps
Always allow regardless of user selection:
- Phone
- Messages
- Emergency / critical access apps as possible within Screen Time constraints
Implementation detail:
- Include these tokens in Always Allowed set before applying shields.
- If tokens are unavailable, show onboarding warning and block enabling Baseline until Screen Time authorization is granted and tokens can be captured.

### Never Block Categories
If user selects categories as never blocked:
- those categories are always excluded from blocking
- they remain accessible even when baseline is enabled and no unlock is active

### Baseline ON behavior
When Baseline Mode is ON:
- Block all app categories by default except:
  - categories in Never Block Categories
  - apps in Always Allowed
  - apps currently temporarily unlocked (activeUnlocks not expired)
Implementation uses:
- store.shield.applicationCategories = .all(except: categoryExceptionsDerivedFromNeverBlock) OR .specific(...) depending on what the API supports best
- store.shield.applications includes all blocked apps OR use category policy plus per-app exceptions
Preferred approach:
- Use category blocking as the primary mechanism, with per-app exceptions for Always Allowed and Temporarily Unlocked.

Baseline OFF:
- clear only baseline store shields
- do not touch project hard block store

## Scheduling
User wanted scheduling optional in addition to always on.

Schedule model:
- daysOfWeek: Set<Int> (1-7)
- startTime: hour/minute
- endTime: hour/minute
- behavior:
  - When within schedule window, baseline is ON (if baselineEnabled true)
  - Outside schedule window, baseline is OFF (even if baselineEnabled true) OR user chooses “Always on” ignores schedule
Decision for this spec:
- baselineEnabled is the master toggle.
- baselineScheduleEnabled controls whether schedule gates enforcement.
- If scheduleEnabled is false: baseline enforced always.
- If scheduleEnabled is true: baseline enforced only during schedule windows.

Scheduling enforcement must be strict using DeviceActivityMonitor:
- start window: apply baseline
- end window: clear baseline store shields (but keep project hard block intact)

## Unlock Flow

### Unlockable Apps Setup
User selects unlockable apps via FamilyActivityPicker.
Persist tokens in baselineUnlockableAppsSelectionData.

When this selection changes:
- Rebuild baselineAppIndex.json by attempting to resolve each token display name:
  - Try ManagedSettings.Application(token:).localizedDisplayName in the main app.
  - If nil, still show the token in UI via SwiftUI Label(token), but mark it as “Cannot be unlocked by typing.”
  - Only include resolvable names in the index.

### Matching rules
Given input string s:
- normalize s
- find unlockable apps whose normalizedName has prefix s
- If exactly 1 match: resolved
- If 0 matches: show “No match”
- If >1 match: continue prompting typing until unique

Auto-resolve behavior:
- When it becomes unique, proceed immediately without requiring Enter.

### Duration
After resolve:
- Prompt for duration:
  - presets: 2, 5, 10 minutes
  - custom: integer minutes from 2 to 60 inclusive
Store durationSeconds = minutes * 60.

### Unlock stacking
Unlocks stack:
- A new unlock does not cancel existing ones.
- Multiple apps can be temporarily unlocked concurrently, each with its own expiry.

### Strict relock and expiry
Unlock expiry must be enforced strictly via DeviceActivityMonitor extension:
- When an unlock is created:
  - add it to activeUnlocks in baselineState.json
  - schedule a monitoring interval ending at expiresAt
- When interval ends:
  - remove expired unlock from activeUnlocks
  - reapply baseline shields immediately

### Auto-open app after unlock (best effort)
After unlocking:
- Attempt to open the app:
  - if known URL scheme or universal link exists: open it
  - else do nothing
No additional UI step is required, since user can open manually from Home Screen.

Maintain a small internal mapping dictionary for common apps used in Israel (WhatsApp, Instagram, YouTube, TikTok, Chrome, Safari) if schemes are known, but treat it as optional and best effort.
Do not block unlocking if opening fails.

## Entry Points

### A) Shortcut “Monk Unlock”
User installs a Shortcut named exactly: “Monk Unlock”

Shortcut steps (high level):
1) Ask for Text input: “App”
2) Ask for Number or choose from menu: 2, 5, 10, Custom
3) Call Monk using URL:
   - monk://unlock?query=<text>&minutes=<int>&source=shortcut
4) Optionally wait for Monk response (not required)
5) End

Important:
- Prefix matching is done inside Monk, not inside the Shortcut.
- Shortcut passes the raw query string and minutes.
- Monk will respond by unlocking if unique match; if ambiguous, Monk opens in-app fallback typing UI with the query prefilled.

### B) Siri
Implement AppIntent + AppShortcutsProvider to allow:
- “Monk WhatsApp 5”
- “Monk <AppName> <Minutes>”

Siri invocation routes through the same AppIntent handler as shortcut URL handling.

### C) Widget
Add a widget “Monk Unlock”
- Single button “Unlock”
- Deep link to monk://quickunlock

Behavior inside Monk on monk://quickunlock:
- Immediately try to open shortcuts://run-shortcut?name=Monk%20Unlock
- If system cannot open the URL (Shortcut missing):
  - Show in-app fallback “Type to Unlock” UI (keyboard focused)

### D) In-app fallback “Type to Unlock”
A minimal screen that:
- has a text field focused on appear
- applies the same prefix matching rules
- once unique: shows duration selector then unlocks
- after unlock: attempts auto-open best effort

This fallback must exist for:
- users without Shortcut installed
- ambiguous query matches
- no match cases

## DeviceActivityMonitor Extension

Add a new target:
- BaselineMonitorExtension (DeviceActivityMonitor extension)

Responsibilities:
1) Enforce strict expiry of temporary unlocks.
2) Enforce schedule start and end events.

Implementation approach:
- The main app schedules monitoring events using DeviceActivityCenter.
- Use one of these two patterns (pick the simpler one in code):
  Pattern 1: One activity per unlock (name includes hash of token + expiry timestamp).
  Pattern 2: One “BaselineUnlockExpiry” activity that always monitors until the nearest expiry; when it fires, reschedule to next nearest.

Schedule enforcement:
- Similarly schedule “BaselineScheduleWindow” monitoring intervals for start/end.
- On start: apply baseline shields.
- On end: clear baseline baseline store shields.

In extension callbacks:
- Read baselineState.json
- Update activeUnlocks (remove expired)
- Apply baseline store shields based on updated state
- Write baselineState.json atomically

Use the same ManagedSettingsStore name as main app:
- ManagedSettingsStore.Name("BaselineBlock")

## BaselineBlockManager (main app)
Create `Monk/Services/BaselineBlockManager.swift` modeled after HardBlockManager.

Public API:
- ensureAuthorization() async -> Bool (reuse AuthorizationCenter)
- applyBaselineIfNeeded(preferences: Preferences) -> Void
- enableBaseline(preferences: Preferences) -> Void
- disableBaseline() -> Void
- registerTemporaryUnlock(query: String, minutes: Int, source: Source) async -> Result
- rebuildAppIndex(preferences: Preferences) -> Void

Core logic:
- Determine if baseline should be active now:
  - baselineEnabled must be true
  - if scheduleEnabled true, must be within schedule window
- Compute exceptions:
  - forced always allowed tokens
  - user always allowed tokens
  - active unlock tokens not expired
- Compute never-block categories from selection
- Apply shields to baseline store only

## UI

### Settings
Add a new section in SettingsView:
- Toggle: Baseline Mode
- Button: Configure Baseline
- Summary: “X unlockable apps, Y never-block categories, schedule: on/off”
- Metrics card: unlock count, total time, top apps

### Baseline Setup Screen
Shown in onboarding after SetupChecklistView “Next” and before paywall.
Also accessible later via Settings.

Flow steps:
1) Explain Baseline Mode in 2-3 sentences.
2) Screen: Pick “Never Block Categories” (FamilyActivityPicker categories only)
3) Screen: Pick “Unlockable Apps” (FamilyActivityPicker apps only)
4) Screen: Pick “Always Allowed Apps” (apps only) with note that Phone and Messages are always allowed
5) Optional: Schedule setup (toggle + time picker)
6) Finish: enable baseline toggle (optional immediate enable)

User must pick manually:
- Do not auto-populate any user-specific selections.
- Only force-allow Phone and Messages and emergency-critical apps.

Warnings:
- If unlockable app names cannot be resolved, show list and tell user those apps cannot be unlocked via typing until name is available.
- If Screen Time is not authorized, block proceeding and route user back to checklist.

## Deep Links and Routing
Add URL handling in app root:
- monk://quickunlock
- monk://unlock?query=...&minutes=...&source=shortcut|siri

Behavior:
- quickunlock: attempt to launch shortcut first, fallback to in-app typing
- unlock: attempt to resolve query
  - if unique: create unlock, schedule expiry monitor, apply baseline shields, log analytics, try auto-open
  - if ambiguous or none: open in-app typing UI with query prefilled and duration preselected

## Acceptance Criteria
1) With Baseline ON, non-allowed apps show Monk shield.
2) Categories selected as never-blocked are accessible without unlock.
3) Shortcut flow:
   - typing prefix resolves uniquely without pressing Enter
   - duration selection works
   - app becomes accessible for the chosen time
   - unlock stacks with other active unlocks
4) Strict expiry:
   - app is re-blocked exactly at expiry even if Monk is closed
5) Widget:
   - tap leads to Shortcut if installed, otherwise shows in-app typing fallback
6) Siri:
   - “Monk WhatsApp 5” triggers the same unlock pipeline
7) Analytics:
   - Settings shows unlock count, total time, top unlocked apps

## Implementation Checklist (file level)
- Add BaselineBlockManager.swift
- Add BaselineStateStore.swift (app group file read/write)
- Add BaselineAppIndexStore.swift (app group file read/write)
- Update Preferences.swift with baseline fields
- Add BaselineSetupView.swift (multi-step)
- Update onboarding flow to show BaselineSetupView after SetupChecklistView and before paywall
- Update SettingsView to include baseline toggle + configure + metrics
- Add deep link routing in app root onOpenURL
- Add AppIntent: UnlockAppIntent.swift
- Add AppShortcutsProvider.swift
- Add new widget “Monk Unlock” with deep link monk://quickunlock
- Add new DeviceActivityMonitor extension target + enforcement logic
- Add UnlockEvent SwiftData model + stats queries

## Testing Plan
- Unit test normalization and prefix matching
- Test ambiguous matches (Instagram vs Instacart)
- Test unlock stacking and independent expiries
- Test schedule boundary triggers
- Test reboot behavior:
  - On reboot, baseline re-applies automatically and temporary unlocks are cleared
- Test missing shortcut:
  - widget opens Monk fallback typing UI

## Current Implementation Status (Jan 30, 2026)
Done so far
- Data model: Added `UnlockEvent` SwiftData model with defaults and registered it in `MonkApp` schema.
- Preferences: Added baseline/intent fields to `Preferences`.
- Shared stores: Added `IntentStateStore` (app-group JSON for flags + active unlocks) and `IntentAppIndexStore` (normalized app name index).
- Enforcement core: Added `IntentBlockManager` (ManagedSettingsStore `.intentBlock`) with project-session override: when a project session is active, baseline is ignored and only the project allowlist (hardBlockSelectionData) + critical apps (Phone/Messages/FaceTime) remain accessible; otherwise baseline allowlist + temp unlocks apply.
- Focus integration: `FocusManager` now calls `IntentBlockManager` on start/stop/init/foreground; legacy HardBlock activation is removed for sessions (project allowlist is reused).
- UI entry: Settings has an “Intent Mode” card with enable toggle and Configure sheet.
- Intent setup UI: Config sheet lets you pick “Always allowed” apps via `familyActivityPicker`; shows count (no name lookups to avoid LS errors). Toggle re-applies shields.

Outstanding / TODO
- Fix app picker reliability: some devices show LaunchServices -54 when opening the picker; suspected Screen Time state/permissions. Keep picker identical to project hard-block flow; avoid name lookups.
- Apply “never block categories” in baseline shields (currently not used).
- Implement unlock flow: deep links `monk://unlock`, Siri/AppIntent, widget quickunlock, and stacking temporary unlocks.
- DeviceActivity monitor: add new monitor extension to enforce strict unlock expiry + schedule windows; schedule nearest-expiry activity from main app.
- Shield UI: optional dedicated Intent shield appearance (separate from project shield).
- Onboarding: slot Intent setup into onboarding sequence.
- Analytics: record `UnlockEvent` instances on unlock creation; surface metrics in Settings.
- Forced apps: consider expanding forced allow list (emergency) once confirmed tokens.

Quick how-to continue
- Picker debugging: ensure Screen Time is ON, capability `Family Controls` and App Group on app + extensions; run on device; if -54 persists, turn Screen Time off, reboot, turn on again, then open picker.
- To change allowlist summary: edit `IntentSetupView.selectedCountLabel`.
- To adjust enforcement precedence: see `IntentBlockManager.applyShields`.

## Intent Mode Implementation Plan (step by step)
1) Data layer & schema
- Add `UnlockEvent` SwiftData model (`Monk/Models/UnlockEvent.swift`) with fields from spec and register it in `MonkApp.sharedModelContainer` schema array.
- Extend `Preferences` with intent-mode fields (keep `baseline` prefix in code for clarity): `baselineEnabled`, `baselineScheduleEnabled`, `baselineScheduleData`, `baselineAlwaysAllowedSelectionData`, `baselineNeverBlockCategoriesSelectionData`, `baselineUnlockableAppsSelectionData`.
- Add lightweight migration/backfill: when Preferences loads, default new flags to false/nil; ensure weeklyGoal migration logic stays intact.

2) Shared app-group state (rename in UI to "Intent Mode")
- Create `IntentStateStore` (app group file `intentState.json`) that mirrors HardBlockStateStore patterns and tracks: enable flags, schedule, selections, active unlocks [{tokenData, expiresAt, durationSeconds, startedAt}].
- Create `IntentAppIndexStore` (file `intentAppIndex.json`) storing {applicationTokenData, displayName, normalizedName}; include normalization helper (lowercase, trim, strip punctuation, collapse spaces). Warn if displayName unresolved.
- Keep using app group `group.com.gbr.Monk`; bootstrap dirs on launch.

3) IntentBlockManager service
- New file `Monk/Services/IntentBlockManager.swift` modeled on HardBlockManager but with ManagedSettingsStore named `.intentBlock`.
- API: `ensureAuthorization()`, `refreshFromPreferences(_:)`, `enableIntentMode(preferences:)`, `disableIntentMode()`, `registerTemporaryUnlock(query:minutes:source:)`, `rebuildAppIndex(preferences:)`, `applyIfNeeded(preferences:activeUnlocks:)`.
- Logic: decide active state (baselineEnabled && (!scheduleEnabled || now in window)); compute allowlists (forced apps Phone/Messages + user always allowed + active unlocks); compute never-block categories; apply shields with category-first policy + app exceptions; leave Project Hard Block untouched.
- On unlock: resolve match via IntentAppIndexStore prefix rules; create unlock entry, persist to IntentStateStore, schedule DeviceActivity monitor to relock at expiry, and attempt best-effort app open.

4) Scheduling & relock enforcement
- Add small schedule model (daysOfWeek set, startTime, endTime) encoded into `baselineScheduleData`.
- IntentBlockManager schedules DeviceActivityCenter intervals for: a) nearest unlock expiry, b) next schedule boundary. Use single "IntentUnlockExpiry" activity pattern and reschedule after each fire.
- Ensure relock runs even if app dead by updating IntentStateStore from the monitor extension then reapplying shields.

5) DeviceActivityMonitor extension target
- Add new target `IntentMonitorExtension` (DeviceActivityMonitor). In handler callbacks: load intentState.json, prune expired unlocks, check schedule, reapply shields via ManagedSettingsStore `.intentBlock`, write state back atomically. Include entitlements for FamilyControls/ManagedSettings/app group.
- Keep existing report extension untouched.

6) Name and strings
- User-facing name is "Intent Mode" everywhere (Settings, onboarding, toasts). Internal code can keep `baseline` prefixes to minimize churn but add `Intent` naming where public.
- Force-allowed copy should mention emergency access and Phone/Messages.

7) UI flows
- Add `IntentSetupView` (multi-step) for Never Block Categories, Unlockable Apps, Always Allowed, optional schedule; enforce Screen Time auth gating; show warnings for unresolved app names.
- Insert into onboarding: after `SetupChecklistView` completion and before paywall, optionally enable Intent Mode.
- Settings: new card with toggle (bind to prefs.baselineEnabled), configure button to IntentSetupView, summary counts (unlockable apps/categories, schedule on/off), and metrics card (unlock count, total time, top apps).

8) Deep links & routing
- Handle `monk://quickunlock` and `monk://unlock?query=&minutes=&source=` in root view/app. Quickunlock tries to open `shortcuts://run-shortcut?name=Monk%20Unlock`; on failure present in-app fallback typing UI.
- Unlock link uses IntentBlockManager: resolve prefix; if unique → unlock + maybe auto-open; if ambiguous/none → present fallback UI with prefilled query/duration.
- Add scene `onOpenURL` routing in `ContentView` or a dedicated router.

9) AppIntents & Siri
- Add `UnlockAppIntent` + `AppShortcutsProvider` to map utterances "Monk <App> <Minutes>". Reuse IntentBlockManager matching/unlock logic; return success/failure phrases. Include shortcuts intent for “Monk Unlock”.

10) Widget entry point
- New widget “Monk Unlock” with single button linking to `monk://quickunlock`. Place in `MonkLiveActivities` or new widget extension; respect dark styling. No text input in widget; relies on app fallback if Shortcut missing.

11) Analytics (local)
- On each unlock creation, write `UnlockEvent` (app display name, token data, startedAt, durationSeconds, source). Provide queries in Settings for last 24h/7d/30d counts, total time, top apps. No intention text stored.

12) Resilience & startup
- On app launch: bootstrap IntentStateStore, reload active unlocks, drop expired, reapply shields if Intent Mode should be active. Ensure reboot cold-start behaves.
- Ensure HardBlock and Intent Mode stores do not conflict (separate ManagedSettings store names & JSON filenames).

13) Testing coverage
- Unit tests: normalization/prefix resolution, ambiguous match handling, unlock stacking & expiry pruning, schedule window evaluation, state encoding/decoding.
- UI tests: quickunlock fallback screen focus, Settings toggle + metrics rendering, deep link handling, Siri/Shortcut intent invocation happy path.
