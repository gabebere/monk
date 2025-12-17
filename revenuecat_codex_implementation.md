# RevenueCat Implementation Guide for Monk (Codex-ready)

This document is intended to give Codex everything needed to implement **RevenueCat + RevenueCatUI Paywalls** for **development/testing** and **production launch** in Monk.

Sources: RevenueCat docs on Debugging, Caching, Offerings, Paywalls display, Sandbox testing, SDK configuration, API keys/auth, and Launch checklist. citeturn2view2turn0search2turn2view1turn2view0turn2view4turn2view5turn2view6turn2view3

---

## 0) Terminology & mental model

### RevenueCat concepts
- **Product**: Store product (Apple product ID like `monk_monthly`, `monk_annually`).
- **Package**: RevenueCat’s normalized wrapper (e.g. `$rc_monthly`, `$rc_annual`) inside an Offering. citeturn2view1
- **Offering**: A grouping of packages/products you show to users (e.g. `monk_subscription`). RevenueCat returns the **current** offering based on your dashboard Default Offering + Targeting/Experiments. citeturn2view1
- **Paywall**: A remote-configured UI definition that can be **paired to exactly one Offering** (when using RevenueCat Paywalls). citeturn2view1turn2view0
- **Entitlement**: A named access flag (e.g. `Monk Subscription` or `pro`) that becomes active when a user buys qualifying products.

### Keys
- **Public SDK key** (“SDK API key” in dashboard): used by the app to configure the SDK. citeturn2view6
- **Secret API key** (`sk_...`): server-only; never ship in the app. citeturn2view6
- **Test Store API key**: a special public key used to talk to RevenueCat’s Test Store. Must not be used for App Store submission. citeturn2view5turn2view3

---

## 1) Dashboard setup (must be correct before code)

### 1.1 Products
- Create Apple products in App Store Connect:
  - `monk_monthly`
  - `monk_annually`
  - (Optional) intro offer: 1-week free trial
- In RevenueCat **Product Catalog**, ensure these products are present/synced.

### 1.2 Entitlements
- Create one entitlement for premium access, e.g.:
  - Identifier: `Monk Subscription` (or better: `pro` / `premium`)
- Attach both products to this entitlement so either subscription unlocks access.

### 1.3 Offerings + Packages
- Create an Offering, e.g. `monk_subscription`.
- Add packages:
  - `$rc_monthly` → `monk_monthly`
  - `$rc_annual` → `monk_annually` citeturn2view1
- Mark the desired Offering as **Default/Current** in the dashboard so the SDK returns it as `offerings.current`. citeturn2view1

### 1.4 Paywalls (RevenueCatUI requires this)
- Create a Paywall (e.g. `monk_paywall_v1`).
- Ensure the paywall references the packages you want (monthly/annual).
- **Assign the Paywall to the Offering** (`monk_subscription`).
  - If the SDK log shows `offering.paywall == nil`, this pairing is missing or configured under a different app/environment/key.

> If you use RevenueCatUI (PaywallView / presentPaywallIfNeeded), the Offering must have a configured Paywall, otherwise you’ll see “Offering has no configured paywall.” citeturn2view0turn2view1

---

## 2) App configuration (Swift / SwiftUI)

### 2.1 Select the correct Public SDK key (critical)
RevenueCat explicitly supports switching between **Test Store** and **real stores** by changing the key used to configure the SDK. citeturn2view5turn2view3

**Recommended build mapping**
- Debug / Development builds:
  - Option A: Test Store public key
  - Option B: iOS (App Store) public key + Apple Sandbox testing
- Release builds:
  - iOS (App Store) public key (never Test Store) citeturn2view5turn2view3

### 2.2 Configure Purchases at app launch
Enable debug logs **before** configuring Purchases. citeturn2view2

```swift
import RevenueCat

func configureRevenueCat() {
    Purchases.logLevel = .debug   // set before configure citeturn2view2
    Purchases.configure(withAPIKey: RCKeys.publicSDKKey,
                        appUserID: nil) // or your stable user id
}
```

**Important iOS note**: if you don’t see debug logs, ensure `OS_ACTIVITY_MODE` isn’t blocking console output in your scheme. citeturn2view2

### 2.3 User identity strategy (App User ID)
RevenueCat can be configured with:
- `appUserID: nil` (anonymous id generated)
- OR a stable user id (recommended once you have accounts)

The app user id persists on-device via caching. citeturn0search2

**Recommended:**
- Configure with `nil` on first launch.
- After login/signup, call `Purchases.shared.logIn(<stableUserID>)` (implementation depends on your auth model).
- On logout, call `Purchases.shared.logOut()` (clears caches). citeturn0search2

---

## 3) Getting offerings + paywall for an offering

### 3.1 Fetch Offerings (source of truth)
Offerings are cached and safe to call often. citeturn0search2turn2view1

```swift
Purchases.shared.getOfferings { offerings, error in
    let current = offerings?.current
    // current?.identifier is the dashboard-selected default/current offering citeturn2view1
}
```

### 3.2 “Set the offering” (how to control which offering shows)
You **don’t set the offering in code** in most cases; you set it in the dashboard by changing the project’s **Default/Current offering**, or by using Targeting/Experiments. citeturn2view1

In code you typically use:
- `offerings.current` (recommended) citeturn2view1
- OR `offerings.all["some_offering_id"]` if you explicitly want a specific offering.

### 3.3 Obtain a Paywall for the offering (RevenueCatUI)
When the Offering has a configured paywall, RevenueCatUI can present it.

There are three primary display patterns on iOS (SwiftUI/UIKit): citeturn2view0
- Present if needed based on an **entitlement**
- Present if needed with **custom logic**
- Present **manually** using `PaywallView` / `PaywallViewController`

Example (manual SwiftUI):
```swift
import RevenueCatUI

if let offering = revenueCat.activeOffering {
    PaywallView(offering: offering)
}
```

**Debug rule:**
- If your logs show `offering.paywall == nil`, the dashboard pairing is not available to your app (wrong key/project/environment, or offering not actually assigned a paywall).

---

## 4) Purchases, restores, and gating access

### 4.1 Purchase flow (RevenueCatUI)
RevenueCatUI handles the purchase UI flow; you gate access by checking active entitlements on `CustomerInfo`.

### 4.2 Restore purchases
Always provide a restore button/flow for App Store compliance and user expectations.

### 4.3 Gating access (single source of truth)
Always gate premium using:
- `CustomerInfo.entitlements.active["<entitlement_id>"]`

RevenueCat caches `CustomerInfo` and refreshes it periodically; it’s safe to call often. citeturn0search2

---

## 5) What information you can get from RevenueCat (and what to use)

### 5.1 From the SDK (client)
Commonly used objects:
- **Offerings**: current offering + packages + mapped products. citeturn2view1turn0search2
- **CustomerInfo**: active entitlements, expiration, purchase history (as exposed), management URLs, etc. (CustomerInfo is cached and refreshed). citeturn0search2
- **Store product metadata**: price, currency, trial eligibility, etc. (Offerings/products cached). citeturn0search2

### 5.2 From the Dashboard
- Subscriptions metrics, customer lists (note: some dashboard areas cache for 1–2 hours). citeturn0search2
- Sandbox toggle in Overview to view non-production purchases (Test Store + platform sandboxes). citeturn2view4

### 5.3 Via REST API (server)
Use server-side API only with **secret API key** (`sk_...`). citeturn2view6
Typical use cases:
- syncing premium state server-side
- analytics/integrations
- customer management workflows

---

## 6) What you should send/store (and what you should NOT)

### 6.1 Must not send
- **Never send/ship `sk_...` secret keys in the app**. citeturn2view6
- Do not “trust” client-side flags for premium without verification if you have a server that grants critical resources.

### 6.2 Recommended to store/send
Depending on your architecture:

**Client → your backend**
- Your own user id (stable)
- RevenueCat **app user id** (once known), so your backend can associate RevenueCat customer records with your user.
- Current entitlement state (optional, for UX), but treat as advisory unless you also verify.

**RevenueCat → your backend**
- Prefer RevenueCat webhooks / integrations (if enabled) for authoritative purchase events (implementation depends on which integration you choose; not covered by the linked page).

**Internal analytics**
- Paywall impression event (include offering id + paywall id)
- Purchase started / purchase completed / restore completed
- Active entitlement changed (from CustomerInfo listener)

---

## 7) Testing strategy (development → sandbox → production)

RevenueCat supports two main testing approaches: citeturn2view4turn1search2

### 7.1 RevenueCat Test Store (fastest dev loop)
- Works “immediately without platform setup” and behaves like real purchases: updates `CustomerInfo`, triggers entitlements, and appears in dashboard. citeturn1search2
- Requires using the **Test Store public key**.

**Hard rule:** Never submit with a Test Store key. citeturn2view3turn2view5

### 7.2 Apple Sandbox (real StoreKit behavior)
RevenueCat automatically detects sandbox vs production purchase environment; no special RevenueCat config needed. citeturn2view4

---

## 8) Debugging & troubleshooting checklist (Codex should implement these helpers)

### 8.1 Enable debug logs
Set `Purchases.logLevel = .debug` before configure. citeturn2view2

### 8.2 Use the Debug UI overlay (iOS)
RevenueCat iOS SDK provides a debug overlay to inspect Offerings/products/entitlements and even purchase from it. citeturn2view2

SwiftUI:
```swift
ContentView()
  .debugRevenueCatOverlay()
```

Or controlled presentation:
```swift
.debugRevenueCatOverlay(isPresented: $debugOverlayVisible)
```

UIKit:
```swift
self.presentDebugRevenueCatOverlay()
```

Notes:
- Debug UI won’t compile for release builds; disable before archiving. citeturn2view2
- You can export configuration JSON to share with RevenueCat support. citeturn2view2

### 8.3 Caching gotchas
- `CustomerInfo` is cached and refreshed:
  - ~5 minutes foreground
  - ~25 hours background
  - after purchase/restore citeturn0search2
- Offerings/products are cached; `getOfferings()` is safe to call often. citeturn0search2
- Paywalls are “prewarmed” and cached session-based (not disk persisted except images). citeturn0search2
- If you need a forced refresh, use the SDK cache invalidation methods (e.g., invalidate customer info cache) per docs. citeturn0search2

### 8.4 “Empty product titles” warning
If StoreKit returns empty localized titles/display names, check App Store Connect localization metadata, device locale, and whether StoreKit Configuration files are being used.

### 8.5 “Offering has no configured paywall”
If `offering.paywall == nil`:
- Verify you are using the correct **platform-specific public key** for the configured app (not Test Store unless that’s where you configured paywalls).
- Verify the offering (`offerings.current.identifier`) matches the dashboard offering you assigned the paywall to.
- Verify the paywall is attached to that offering and contains packages.

---

## 9) Production launch checklist (must-do items)

Use RevenueCat’s pre-launch checklist and follow at least this subset. citeturn2view3turn2view5

### Critical
- **Replace Test Store API key** with the correct iOS platform public SDK key before App Store submission. citeturn2view3turn2view5

### Recommended
- Ensure entitlements gate the correct premium features.
- Ensure restore purchases is present and works.
- Verify paywall renders and purchases complete on:
  - Apple sandbox (TestFlight if applicable)
  - real device
- Confirm dashboard sandbox toggle shows non-production purchases during testing. citeturn2view4

---

## 10) Minimal “golden path” implementation plan (Codex execution order)

1. **Decide keys per build**:
   - Debug uses Test Store OR iOS sandbox key; Release uses iOS platform key only. citeturn2view5turn2view3
2. Configure Purchases at launch with `.debug` logging in debug builds. citeturn2view2
3. Fetch `offerings.current` and store as `activeOffering`. citeturn2view1
4. Present RevenueCatUI:
   - `PaywallView(offering: activeOffering)` (manual) OR `presentPaywallIfNeeded` patterns. citeturn2view0
5. Gate access using `CustomerInfo.entitlements.active["<entitlement>"]`. citeturn0search2
6. Add Restore button.
7. Add Debug overlay behind a debug flag and remove from release builds. citeturn2view2
8. Implement logging for:
   - current offering id
   - whether `offering.paywall` is nil
   - package mapping (`$rc_* -> monk_*`)
9. Validate with:
   - Test Store (optional) citeturn1search2
   - Apple sandbox citeturn2view4
10. Before submission: ensure iOS platform key is used, not Test Store. citeturn2view3turn2view5
