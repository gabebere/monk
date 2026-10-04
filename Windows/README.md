# Monk for Windows

Monk for Windows carries the Mac app's commitment model to Windows: choose one
intention, a duration, the applications you may use, and the websites you may
visit. Everything else is closed until the commitment expires. At zero, Monk
keeps enforcing until you explicitly extend or end the completed session.

## What is implemented

- A Windows 10/11 tray application with an `Alt+Space` command window.
- Installed-application discovery and allowlist-only process enforcement.
- Persisted sessions that resume enforcement after sign-in or an app restart.
- Default blocking between timed sessions with a separate always-allowed list.
- A Chromium extension for domain allowlisting in Chrome, Edge, Brave, and
  other Chromium browsers.
- A native-messaging host that shares the current policy with the extension
  without sending focus data over the network.
- A modern per-user Inno Setup installer with launch-at-sign-in registration
  and browser-host setup.

The first implementation is intentionally local-only. Windows cannot access
the user's private CloudKit database, so cross-device sync needs an Apple-hosted
bridge or a product decision to introduce another private sync backend.

## Build on Windows

Requirements:

- Windows 10 version 2004 or newer, or Windows 11
- .NET 8 SDK
- Inno Setup 6 (only needed to make the installer)

From PowerShell:

```powershell
./scripts/build.ps1
```

The build runs dependency-free core smoke tests before publishing.

The published app is written to `artifacts/app`. If Inno Setup is installed,
the installer is written to `artifacts/installer`.

Release gates and remaining Mac parity work are tracked in
[`ROADMAP.md`](ROADMAP.md).

## Browser setup for development

The installer registers the local native host. Until the Monk extension has a
Chrome Web Store / Edge Add-ons release ID, load `browser-extension` as an
unpacked extension from the browser's extensions page with Developer mode on.
The checked-in public manifest key keeps the unpacked extension ID stable.

## Enforcement boundary

The app closes ordinary applications owned by the signed-in user and prevents
normal app exit while blocking is active. Its persisted state reactivates after
restart. A user with administrator access can still stop or remove a desktop
application through Task Manager, recovery mode, or system tools. Production
tamper resistance requires the planned signed Windows service described in
[`ARCHITECTURE.md`](ARCHITECTURE.md); it should be added only alongside signed
binaries and a tested recovery path so Monk cannot accidentally lock a user out.
