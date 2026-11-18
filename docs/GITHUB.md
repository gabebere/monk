# GitHub operating model

Repository: [gabebere/monk](https://github.com/gabebere/monk). Visibility: public. Default branch: `main`. One monorepo owns the Apple product, shared contract, experimental Windows source, engineering documentation, and delivery tooling.

This document defines the intended operating model. Checked-in templates and workflow files do not automatically enable repository rules. At the 2026-11-18 audit, the live repository had no rulesets. [`.github/repository-settings.json`](../.github/repository-settings.json) is the declarative configuration; apply/audit tooling and the resulting live state must be recorded separately.

## Branches and review

Use short-lived `feature/...`, `fix/...`, `docs/...`, or `release/...` branches from current `main`. Existing `codex/...` task branches remain valid. Open one focused pull request per coherent behavior/contract change. Shared sync changes should be reviewed with their platform integrations, tests, schema implications, and migration notes together.

Use draft PRs for work that compiles only partially or lacks device evidence. The PR template records automated verification separately from real-device gates. Prefer squash merge and delete merged branches. Do not create permanent phone/tablet forks or a long-lived `develop` branch. A release branch is justified only for maintaining an already shipped version while the next minor version proceeds.

The repository owner is the initial code owner; [CODEOWNERS](../.github/CODEOWNERS) makes review routing explicit without inventing teams. When more maintainers join, assign actual handles/team slugs to platform and infrastructure paths. A solo maintainer cannot supply an independent self-review; any required-review rule needs a documented practical maintainer path. Do not pretend an automated agent review substitutes for release approval.

## Required checks

The Apple CI workflow should provide these stable status names:

- `Repository validation`
- `iPhone and iPad build`
- `Mac build and tests`

Require the final commit's checks before merging, block force pushes/deletion of `main`, require resolved discussions, and limit bypass to documented maintainer recovery. Test the rule against a draft PR before making it a hard dependency. CI must run on pull requests without signing/notarization secrets; a simulator build does not establish Family Controls behavior.

## Issues and ownership

Use the bug and feature templates. Bug reports include platform, OS, version/build, reproduction, expected behavior, sync environment, and redacted diagnostics. Never request Screen Time tokens, signing files, or a private database dump in public issues. Security reports use [SECURITY.md](../SECURITY.md).

Use a small label vocabulary: `platform:mobile`, `platform:mac`, `platform:shared`, `area:sync`, `area:release`, `type:bug`, `type:docs`, `priority:p1`, and `blocked:apple`. The 1.0 milestone can reference the [audit issue register](issues/README.md); labels/milestones are not claimed to exist remotely until applied. Each blocking issue needs a concrete acceptance condition and an owner, not only a broad roadmap title.

## Releases and credentials

Use a single `vMAJOR.MINOR.PATCH` Apple source tag and a draft GitHub release while gates are open. Attach only verified Mac distribution artifacts/checksums and release notes; TestFlight/App Store delivery is recorded with the mobile build and availability. Never attach development provisioning profiles or `.xcarchive` bundles containing private signing material to a public release.

Signed release operations run deliberately on a trusted maintainer Mac or a protected release environment. Keep credentials in the Keychain or scoped environment secrets, never in source or pull-request workflows. Production deployment and publication need release-approver sign-off after the artifacts and evidence are reviewable. Repository organization changes do not authorize silently creating a public `v1.0.0` release.

## Settings handoff

Repository configuration is versioned and reviewed through pull requests. Merging these files does not apply live repository settings. At the 2026-11-18 audit, the live settings had not yet been reconciled with this manifest. Applying administrative settings is a separate operation from uploading source, merging a PR, or publishing a release.

The default command prints an offline plan. `--check` performs the read-only live audit, and `--apply` applies merge settings. Activating rules additionally requires all three CI checks to be green on the current default-branch SHA:

```sh
python3 script/configure_github.py
python3 script/configure_github.py --check
python3 script/configure_github.py --apply
python3 script/configure_github.py --apply --activate-rules
```

Run the checked-in tool with authenticated repository administration access. The local configuration and available authentication may not permit every setting on every GitHub plan. Record unapplied controls rather than claiming protection from files alone. No change to repository visibility or transfer to a new organization is part of this setup.
