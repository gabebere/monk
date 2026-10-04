# Windows delivery plan

## Implemented foundation

- Product state machine and persisted recovery
- Tray app, `Alt+Space` panel, composer, active timer, and expiry decision
- Installed-app discovery, app allowlisting, and default blocking
- Chromium domain allowlisting with a local-only native messaging bridge
- Launch at sign-in, branded executable, setup guide, and per-user installer
- Dependency-free smoke tests for URL and commitment rules

## Release gates

1. **Windows validation** — build on clean Windows 10 x64, Windows 11 x64, and
   Windows 11 ARM64 machines; exercise sleep, restart, multi-monitor, upgrades,
   and expired-session recovery.
2. **Signed enforcement service** — move the process guardian and authoritative
   deadline into a Windows service, add a recovery-safe upgrade protocol, and
   test tamper and crash behavior.
3. **Browser distribution** — publish the extension to Chrome Web Store and
   Microsoft Edge Add-ons, replace the unpacked setup step with store install
   links, and validate Brave/Chromium instructions.
4. **Signing and reputation** — Authenticode-sign every executable and the
   installer, timestamp signatures, run malware scans, and establish SmartScreen
   reputation before public release.

## Parity follow-ups

| Capability in the current Mac worktree | Windows status |
| --- | --- |
| Focus composer and active-session UI | Implemented |
| App and website allowlists | Implemented |
| Default blocking and always-allowed apps | Implemented |
| Restore after restart; cannot end early | Implemented at app level |
| Launch at sign-in | Implemented by installer |
| Browser-history suggestions | Planned; local-only Chromium history readers |
| Individually selectable Microsoft Store apps | Implemented with AppUserModelID/package-family matching |
| Record completed focus in Calendar | Planned; requires a no-account Windows UX decision |
| Private CloudKit cross-device sync | Blocked on platform design; Windows has no native private-CloudKit client |
| Production tamper resistance | Planned signed service release gate |

The sync choice needs an explicit product decision. The privacy-preserving
options are an Apple-hosted bridge that keeps CloudKit authoritative, or a new
end-to-end-encrypted backend. Adding a Monk account merely for Windows would
conflict with the project's current product boundary.
