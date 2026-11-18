# Contributing

Monk is maintained as one monorepo with a universal iPhone/iPad app, a native Mac app, shared portable contract, and experimental Windows code. Start with the [engineering handbook](docs/README.md) and [GitHub operating model](docs/GITHUB.md).

## Product boundaries

Preserve allowlist-only behavior and binding active commitments. Cross-device intent belongs in the user's private CloudKit database. Screen Time tokens, local mappings, and filesystem paths stay on their device. Accounts, analytics, advertising, subscriptions, broad integrations, or a new onboarding system require an explicit product decision.

## Change workflow

1. Branch from current `main`; keep a PR focused on a coherent behavior or contract.
2. Keep platform UI/enforcement inside its platform directory. Review target membership when adding shared source.
3. Add/update meaningful tests for parsing, policy, persistence, enforcement, identity, or sync behavior.
4. Run the relevant commands below and report pass/fail/blocked accurately.
5. Update product/data/runbook documentation when behavior, schema, operational commands, or release gates change.
6. Complete the PR template with compatibility, migration, entitlement, and validation implications.

```sh
./script/ci.sh validate
./script/ci.sh mobile
./script/ci.sh mac
```

A shared-model/configuration change requires both Apple builds. Mobile/native enforcement and distribution changes also need signed-device acceptance; simulator or model tests alone are insufficient. Windows verification remains `./Windows/scripts/build.ps1` from PowerShell.

## Style and scope

Follow Swift API Design Guidelines, four-space indentation, same-line braces, and one primary type per file. Prefer small SwiftUI views with clear state ownership and system frameworks over new dependencies. Do not move the source tree or split repositories just for appearance; dependency clarity and repeatable builds are the goal.

## Privacy and release hygiene

Never commit `Configurations/Local.xcconfig`, signing credentials/profiles, private CloudKit exports, raw tokens, local journals, build output, or notarization credentials. Keep production secrets out of pull-request workflows. Use [SECURITY.md](SECURITY.md) for vulnerability reports.

Production schema changes must be additive and reviewed with compatibility tests. Keep mobile app/extension build versions aligned. A version bump does not authorize a public release: [release gates](docs/runbooks/RELEASE_CHECKLIST.md) and concrete artifact approval still apply.
