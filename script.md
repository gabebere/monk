# Monk Onboarding Commercial Blend Spec (`script.md`)

Last updated: 2026-02-17

## 1) Summary

Create one production-ready onboarding commercial spec that blends:
- Monk's real, shipped capabilities and visual language.
- Your friend's cinematic 30-second concept and pacing style.

Locked decisions for this cut:
- Narrative priority: `Focus OS first`
- Onboarding role: `Replace current intro`
- Duration: `Exactly 30.0s`
- Format: `Silent + haptics`
- Ending line: `Keep "Make your phone a tool again."`
- Rewrite level: `Moderate rewrite` (keep cinematic grammar, fix product truth)

## 2) Current Monk Capability Baseline

This script must only claim what Monk currently ships.

| Capability | Product truth to represent | Current source anchors |
|---|---|---|
| Authentication | Apple/Google/email sign-in gateway before app shell | `Monk/Views/AuthGatewayView.swift`, `Monk/Services/AuthManager.swift` |
| Core loop | Create/select project + task, then start/stop focus sessions | `Monk/Views/HomeView.swift`, `Monk/Views/Tasks/ScheduledTasksView.swift`, `Monk/Services/FocusManager.swift` |
| Optional hard blocking | Project-level hard block with Screen Time authorization | `Monk/Services/HardBlockManager.swift`, `Monk/Views/HomeView.swift` (project create/edit) |
| Session history editing | Session list with edit/delete and project reassignment | `Monk/Views/HistoryView.swift`, `Monk/Views/EditSessionView.swift` |
| Insights model | Weekly project goal planning/progress and focus summaries | `Monk/Views/InsightsView.swift`, `Monk/Services/InsightsAnalyzer.swift` |
| Calendar logging | Optional per-device calendar event creation for sessions | `Monk/Services/CalendarIntegration.swift`, `Monk/Views/SetupChecklistView.swift`, `Monk/Views/SettingsView.swift` |
| Location in calendar | Optional location capture for calendar entries | `Monk/Services/LocationProvider.swift`, `Monk/Services/FocusManager.swift` |
| Health import | Optional workout/sleep import into calendar | `Monk/Services/HealthSyncService.swift`, `Monk/Views/SettingsView.swift` |
| Cross-device mirroring | Session start/stop mirroring through CloudKit events | `Monk/Services/MirrorSyncService.swift` |
| Live surfaces | Live Activity + widget snapshots from app group data | `Monk/Services/LiveActivityManager.swift`, `Monk/Shared/Snapshot/SnapshotWriter.swift`, `MonkLiveActivities/` |

## 3) Current Visual Language Baseline

The commercial should look native to Monk's current design language.

- Color and tone:
  - Dark cinematic gradients (blue/purple/teal families).
  - High-contrast white/off-white typography and iconography.
  - Glass/translucent card treatments with subtle strokes.
- Motion style:
  - Slow drift, pulse, and eased transitions.
  - Controlled and calm, not playful/cartoonish.
  - Meaningful transitions tied to state changes.
- Core hero motif:
  - Glowing `Time to focus?` call-to-action as the emotional center.
- Brand mark:
  - Black field + serif off-white `Monk` wordmark lockup.

Visual anchors in code:
- `Monk/Design/Theme.swift`
- `Monk/Views/HomeView.swift`
- `Monk/Views/OnboardingStoryView.swift`
- `Monk/Views/Projects/ProjectGridListView.swift`

## 4) Friend Concept Breakdown

### Keep

- Geometric abstraction (dot/swarm/feed/tile/grid language).
- Chaos-to-calm emotional arc.
- Sparse copy with short, readable lines.
- Haptics as pacing instead of voice-over.
- Heavy, intentional timing and transition rhythm.

### Change

- Remove implied feature behavior Monk does not currently ship.
- Replace voice-command temporary unlock framing with real Monk actions:
  - choose project
  - choose task
  - start focus
  - optional shielding
  - visible outcome/progress

## 5) Gap Analysis and Blend Rules

### Unsupported beat to remove

Remove this beat from the concept:
- `"Say it." -> "WhatsApp, 5 minutes"` plus autonomous timed unlock/relock flow.

Reason:
- Monk currently does not ship a natural-language temporary unlock mechanic in onboarding or session flow.

### Blend rules for this cut

1. Keep the cinematic shell (geometry, pacing, haptics) from your friend's concept.
2. Make each scene map to a shipped Monk behavior or truthful product promise.
3. Present hard blocking as optional and permission-dependent, never mandatory.
4. Present calendar/location/health as optional outcomes, not guaranteed defaults.
5. Preserve the final brand promise: `Make your phone a tool again.`

## 6) Final 30s Script (Locked Cut)

Format: silent film grammar with haptics and on-screen copy.

| Time | Visual | On-screen text | Haptic cue | Monk truth anchor |
|---|---|---|---|---|
| 0.0-2.2s | Black screen, single center dot pulse | "A phone is a tool." | 2 light impacts on pulses | Brand premise |
| 2.2-6.5s | Dot multiplies into restless swarm inside phone outline | "It should obey your intention." | Light irregular taps | Attention friction |
| 6.5-9.8s | Swarm morphs to infinite feed + accelerating time counter | "Most apps are built to pull you in." | Tick sequence + 1 heavy at cut | Problem statement |
| 9.8-12.5s | Hard cut to stillness, slicing line collapses feed to one tile | "Monk changes the default." | 1 rigid impact, then silence | Product turn |
| 12.5-15.6s | Tile expands to project grid, label swaps `Project: Study` -> `Project: Work` | "Choose a project." | 1 soft selection per swap | Real project model |
| 15.6-19.0s | One task remains; `Time to focus?` CTA activates; timer starts | "Choose one task. Start focus." | 1 heavy impact on start | Real task+session flow |
| 19.0-22.8s | Distracting tiles dim behind shield layer | "Shield distractions when needed." | 1 light lock impact | Optional hard block truth |
| 22.8-26.8s | Session completes; calm state; history/calendar/progress cues appear | "Your focus becomes visible." | 1 soft success | History + calendar + weekly progress |
| 26.8-30.0s | Fade to black; Monk logo/title card settles | "Monk" / "Make your phone a tool again." | 1 very soft success at settle | Closing promise |

## 7) SwiftUI Implementation Blueprint (for next step)

This section defines the implementation contract for coding the onboarding commercial.

### Proposed scene model

```swift
struct CommercialSceneSpec: Identifiable {
    let id: String
    let start: TimeInterval
    let end: TimeInterval
    let copy: [String]
    let visualState: CommercialVisualState
    let hapticEvents: [CommercialHapticEvent]
}

enum CommercialVisualState {
    case dot
    case swarm
    case feed
    case collapse
    case projectGrid
    case taskStart
    case shielded
    case outcomes
    case endCard
}

enum CommercialHapticCue {
    case light
    case rigid
    case heavy
    case success
}

struct CommercialHapticEvent: Identifiable {
    let id: String
    let at: TimeInterval
    let cue: CommercialHapticCue
}
```

### Proposed onboarding view contract

```swift
struct OnboardingCommercialView: View {
    let onFinish: () -> Void
    let onSkip: () -> Void
}
```

### Timeline driver

- Use one timeline authority:
  - `TimelineView(.animation)` plus elapsed-time resolver, or
  - one `Task`-driven scheduler with scene markers.
- Drive visual states by scene boundaries, not frame-by-frame state mutation.
- Trigger haptics only on scheduled transition markers.
- Total runtime must complete at exactly `30.0s`.

### Motion and composition guidance

- Build geometry with:
  - `Circle()`, `RoundedRectangle`, `Capsule`, `Path`.
- Use eased transitions:
  - `withAnimation(.easeInOut(duration: ...))`
  - selected spring transitions where emphasis is needed.
- Keep one accent color active at a time.
- Preserve a dense black backdrop and off-white text treatment.

### Accessibility requirements

- Respect `Reduce Motion`:
  - swap complex swarm/feed animations for simplified crossfades and static geometry states.
- Disable haptic calls when haptics are unavailable/off.
- Keep text line duration readable in one pass.

### Onboarding control requirements

- `Skip` must be visible and tappable early.
- `Skip` should route immediately to the next onboarding step.
- Completion should set the same app flag currently used (`hasSeenOnboarding`).

## 8) Important Interfaces and Types (planned, not implemented in this step)

- New view:
  - `OnboardingCommercialView`
- New script-driving types:
  - `CommercialSceneSpec`
  - `CommercialVisualState`
  - `CommercialHapticCue`
- Integration updates:
  - `ContentView` onboarding gate swaps from `OnboardingStoryView` to `OnboardingCommercialView`.
  - Keep `OnboardingStoryView` available as fallback/preview during rollout.

## 9) Test Cases and Scenarios

### 1. Truthfulness audit

- Every line in the commercial maps to shipped Monk capabilities.
- No suggestion of voice-command temporary unlocks.
- No promise that optional settings are always enabled by default.

### 2. Timing and readability

- Runtime is exactly `30.0s`.
- Each copy line is readable once at natural pace.
- No abrupt text flicker or rapid overwrite.

### 3. Haptic pacing

- Early scenes: restless cadence.
- Late scenes: sparse, controlled cadence.
- No frame-level haptic spam; only scheduled transition cues.

### 4. Onboarding UX

- Skip path exits cleanly and continues setup sequence.
- Non-skip path sets onboarding completion flag consistently.
- Re-entry behavior matches existing onboarding state machine.

### 5. Accessibility and fallback

- Reduced-motion mode remains coherent and emotionally equivalent.
- Haptic-disabled environments still communicate phase changes visually.

## 10) Assumptions and Defaults

- Silent delivery (no voice-over/music) is intentional.
- Palette remains black/off-white with one accent emphasis at a time.
- Hard blocking is optional and permission-gated.
- Calendar, location, and health are optional outcomes and must be framed as such.
- This deliverable is spec-only and does not implement UI code in this step.

## 11) Line-by-Line Truth Map

This map is the final guardrail before implementation.

| Script line | Product behavior it represents | Notes |
|---|---|---|
| "A phone is a tool." | Brand framing | Positioning statement, not feature claim |
| "It should obey your intention." | Focus/session intentionality | Supported by project/task-directed flow |
| "Most apps are built to pull you in." | Attention-friction setup | Problem framing |
| "Monk changes the default." | Shift to focus-first workflow | Transition into product scenes |
| "Choose a project." | Project creation/selection | Shipped in Home/Projects flows |
| "Choose one task. Start focus." | Scheduled tasks + session start | Shipped today |
| "Shield distractions when needed." | Optional hard block | Permission-dependent; framed correctly |
| "Your focus becomes visible." | History + calendar + progress surfaces | Shipped, with optional settings caveat |
| "Make your phone a tool again." | Brand promise | Matches chosen final tagline |
