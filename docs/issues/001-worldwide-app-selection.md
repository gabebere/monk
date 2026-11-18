# 001 — Worldwide mobile app selection and cross-device mapping

Priority: P1. Status: code remediation implemented in the 1.0 candidate; distributed-device acceptance remains open.

## Problem and evidence

`Monk/Services/CrossDeviceFocusService.swift` uses `FamilyActivityData.shared.installedApplications` only when authorization is `approvedWithDataAccess` on iOS/iPadOS 26.4+. It uses these results to turn opaque Screen Time tokens into names and bundle identifiers for sync. `Monk/Views/Focus/MobileApplicationSearchPicker.swift` offers app search and a system-picker fallback. The original UI treated OS availability as sufficient reason to keep offering search authorization.

Apple's [FamilyActivityData documentation](https://developer.apple.com/documentation/familycontrols/familyactivitydata) states that customer installations require an EU location and an EU Apple Account region; development testing can work in any region. [AuthorizationStatus.approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess) explains that outside the EU this authorization status is unavailable. A development build working in Israel does not establish equivalent TestFlight/App Store behavior.

## Concrete failure scenarios

1. A non-EU customer installs a release, grants ordinary Screen Time access, and can select tokens through Apple's picker, but installed-app search never becomes available.
2. A phone publishes a focus containing local tokens. Without the data-access API, it cannot automatically publish corresponding portable identities; a peer cannot infer what those tokens mean.
3. A Mac publishes an allowed app. A mobile peer lacks the data-access API and cannot resolve it automatically; silently showing “synced” would conceal missing access.

## Required behavior

Token-based local selection must always be usable with ordinary approved Screen Time access. Optional search must use actual authorization/data availability, explain an unsuccessful request, and stop presenting itself as a prerequisite. Portable requested apps must expose unresolved local equivalents and allow the person to map each to a locally picked token. Tokens and mappings stay local. A mapping must be scoped to the requested app and must not broaden access by an ambiguous display-name guess. Mac-only app selection must remain available even with no mobile catalog.

## Compatibility and migration

Retain existing saved `FamilyActivitySelection` data and automatic mappings. Do not upload raw tokens as a workaround. Older OS versions retain Apple's picker. A change in regional eligibility or authorization must fall back without deleting saved selections. Local mappings must survive ordinary relaunches and upgrades.

## Candidate remediation

The app-selection UI always provides Apple's local token picker, independently of optional catalog search. It removes the repeated search-authorization prompt and shows search only when real catalog data is available. `MobileApplicationMappingSheet` provides a one-app picker for an unresolved portable request; `saveApplicationMapping` validates exactly one token and saves it locally. Unmatched active/default requests remain actionable in the mobile views. Automatic mobile-origin naming remains optional: an unnamed local token cannot be made portable by the UI alone.

## Acceptance evidence

- Test ordinary `.approved`, unavailable catalog, denied data access, supported data access, and empty catalog separately.
- On non-EU release-signed phone and tablet builds, select apps, begin a focus, map a remotely requested app, and verify only the intended app becomes available.
- Verify Mac-only selections remain searchable without a mobile catalog.
- Revoke data access and relaunch; local token selection remains functional.
- Verify no token or local mapping enters a CloudKit record or log.

A worldwide fallback in source does not close the regional release-signed device checks.
