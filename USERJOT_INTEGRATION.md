# UserJot Integration – Current State & Open Questions

## Current Situation
- Monk uses the native UserJot iOS SDK.
- Settings has a single feedback button that opens the native UserJot sheet.
- We identify the signed-in user before showing feedback:
  - `UserJot.identify(id: currentUser.id, email: currentUser.email, name: currentUser.name)`
- Problem: users still see a UserJot login prompt when posting feedback, so the flow is not truly one-tap.

## Web Guide vs Native SDK
- The UserJot guide describes a web widget flow with backend-signed tokens (HMAC-SHA256 of the user ID using the UserJot secret).
- Web flow:
  1) Backend signs user ID with the UserJot secret.
  2) Frontend loads the web SDK (`uj`) and calls `uj.init(...)`.
  3) Frontend calls `uj.identify({ id, email, signature, ... })`.
  4) With Automatic Login + signed tokens enabled, the web widget logs in the user automatically.
- Native iOS SDK differences:
  - Provides `UserJot.identify(...)`.
  - Does not currently expose a signature parameter like the web flow, so we cannot mirror the web auto-login in the native sheet.

## What we need from UserJot
1) Does the iOS SDK support signed tokens/SSO?
   - If yes: what API accepts user ID + server-generated HMAC/JWT? Need a code sample for iOS with signed tokens.
2) If native does not support signed tokens:
   - Is the only way to get seamless auto-login to embed the web widget in a WKWebView and use the web signed-token flow?

## Next Step Options (once UserJot clarifies)
1) Stay native (if iOS signed tokens are supported):
   - Add backend endpoint `/api/userjot-token` that returns `{ id, email, signature }` where `signature = HMAC_SHA256(id, USERJOT_SECRET)`.
   - Call the native API that accepts the signature (if available) before showing the sheet.
   - Goal: tap “Feedback” → native sheet opens → user can post without logging in.
2) Hybrid web view (if signed tokens are web-only):
   - Add the same backend endpoint for the signature.
   - Add a WKWebView that loads a small HTML page with the web SDK, calls `uj.init(...)` and `uj.identify({ id, email, signature, ... })`, then `uj.showWidget(...)`.
   - Goal: tap “Feedback” → WKWebView opens → web widget is already authenticated (no login prompt).

## Why users still see a login prompt
- The current native SDK flow does not replicate the web “auto-login with signed tokens” flow because the native API (as used) does not take a signature/token. Until UserJot provides an iOS API for signed tokens—or we embed the web widget with signed tokens—users will still be asked to log in.
