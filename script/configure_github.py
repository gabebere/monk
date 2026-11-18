#!/usr/bin/env python3
"""Review, audit, or apply Monk's repository settings using authenticated gh.

The default is an offline plan. Rules are activated only after their named checks
have succeeded on the current default branch. This prevents requiring checks
before the first CI workflow has been merged. No credentials are read or printed.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / ".github" / "repository-settings.json"


def api(path: str, method: str = "GET", payload: Any = None) -> Any:
    command = ["gh", "api", "--hostname", "github.com", "--method", method,
               "-H", "Accept: application/vnd.github+json", path]
    if payload is not None:
        command.extend(["--input", "-"])
    try:
        result = subprocess.run(
            command, input=None if payload is None else json.dumps(payload),
            text=True, capture_output=True, check=True, timeout=60,
        )
    except FileNotFoundError as error:
        raise RuntimeError("Install GitHub CLI (gh) and authenticate with repository administration access.") from error
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("GitHub request timed out; no retry was made automatically.") from error
    except subprocess.CalledProcessError as error:
        # gh owns authentication. Do not echo command input or environment.
        raise RuntimeError(error.stderr.strip() or "GitHub request failed.") from error
    return json.loads(result.stdout) if result.stdout.strip() else None


def load_manifest(path: Path) -> dict:
    manifest = json.loads(path.read_text())
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", manifest["repository"]):
        raise ValueError("repository must be an owner/name pair")
    if manifest["ruleset"]["target"] != "branch":
        raise ValueError("Only branch rulesets are managed by this script")
    if manifest["ruleset"]["conditions"]["ref_name"]["include"] != ["~DEFAULT_BRANCH"]:
        raise ValueError("The managed ruleset must target only the default branch")
    if manifest["ruleset"].get("bypass_actors"):
        raise ValueError("This manifest must not introduce bypass actors")
    return manifest


def required_checks(manifest: dict) -> set:
    return {
        check["context"]
        for rule in manifest["ruleset"]["rules"]
        if rule["type"] == "required_status_checks"
        for check in rule["parameters"]["required_status_checks"]
    }


def latest_checks_passed(check_runs: list, required: set) -> bool:
    # A prior passing attempt must not hide a newer failed or running attempt.
    newest = {}
    for check in check_runs:
        name = check.get("name")
        if name not in newest or check.get("id", 0) > newest[name].get("id", 0):
            newest[name] = check
    return bool(required) and all(
        name in newest and newest[name].get("status") == "completed"
        and newest[name].get("conclusion") == "success"
        for name in required
    )


def fetch_check_runs(base: str, sha: str) -> list:
    checks = []
    page = 1
    while True:
        response = api(f"{base}/commits/{sha}/check-runs?per_page=100&page={page}")
        batch = response.get("check_runs", [])
        checks.extend(batch)
        if len(batch) < 100:
            return checks
        page += 1


def settings_diff(actual: dict, desired: dict) -> dict:
    return {
        key: {"actual": actual.get(key), "desired": value}
        for key, value in desired.items() if actual.get(key) != value
    }


def normalize_ruleset(value: dict) -> dict:
    # GitHub adds IDs/timestamps/source fields and may reorder rules/checks.
    def canonical(item):
        if isinstance(item, list):
            return sorted((canonical(part) for part in item), key=lambda part: json.dumps(part, sort_keys=True))
        if isinstance(item, dict):
            return {key: canonical(part) for key, part in item.items()}
        return item
    return canonical({key: value.get(key, []) if key == "bypass_actors" else value.get(key)
                      for key in ("name", "target", "enforcement", "bypass_actors", "conditions", "rules")})


def rulesets_equal(actual: dict, desired: dict) -> bool:
    # The API may add optional/default parameters. Compare the fields this
    # manifest manages while still detecting extra rules or check contexts.
    def managed(value, template):
        if isinstance(template, dict) and isinstance(value, dict):
            return {key: managed(value.get(key), part) for key, part in template.items()}
        if isinstance(template, list) and isinstance(value, list):
            if template and all(isinstance(part, dict) for part in template):
                discriminator = next((key for key in ("type", "context")
                                      if all(key in part for part in template)), None)
                if discriminator:
                    templates = {part[discriminator]: part for part in template}
                    return [managed(part, templates.get(part.get(discriminator), part))
                            if isinstance(part, dict) else part for part in value]
            return value
        return value
    return normalize_ruleset(managed(actual, desired)) == normalize_ruleset(desired)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Read GitHub and fail on managed settings drift")
    mode.add_argument("--apply", action="store_true", help="Apply the reviewed settings manifest")
    parser.add_argument("--activate-rules", action="store_true", help="With --apply, activate branch rules after checking CI on main")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args(argv)
    if args.activate_rules and not args.apply:
        parser.error("--activate-rules requires --apply")
    manifest = load_manifest(args.manifest)
    if not args.check and not args.apply:
        print(json.dumps(manifest, indent=2))
        print("Plan only. --check audits GitHub; --apply changes merge settings; --apply --activate-rules also enables branch rules after CI passes.")
        return 0

    base = "repos/" + manifest["repository"]
    repository = api(base)
    if not repository.get("permissions", {}).get("admin", False):
        raise RuntimeError("Repository administration access is required; nothing was changed.")
    rules = api(base + "/rulesets?per_page=100")
    matches = [rule for rule in rules if rule["name"] == manifest["ruleset"]["name"]]
    if len(matches) > 1:
        raise RuntimeError("Multiple managed rulesets have the same name; inspect GitHub before applying.")
    existing = api(base + "/rulesets/" + str(matches[0]["id"])) if matches else None
    differences = settings_diff(repository, manifest["settings"])
    rules_match = existing is not None and rulesets_equal(existing, manifest["ruleset"])
    print(json.dumps({"repository": manifest["repository"], "settings_drift": differences,
                      "ruleset_matches": rules_match}, indent=2))
    if args.check:
        return 1 if differences or not rules_match else 0

    if args.activate_rules:
        branch = api(base + "/branches/" + repository["default_branch"])
        if not latest_checks_passed(fetch_check_runs(base, branch["commit"]["sha"]), required_checks(manifest)):
            raise RuntimeError("Merge and run the CI workflow on the default branch first. Required checks must all pass; nothing was changed.")
    if differences:
        api(base, "PATCH", manifest["settings"])
        print("Applied repository merge settings.")
    if args.activate_rules and not rules_match:
        path = base + "/rulesets" + ("/" + str(existing["id"]) if existing else "")
        api(path, "PUT" if existing else "POST", manifest["ruleset"])
        print("Activated default-branch quality gates.")
    elif not args.activate_rules:
        print("Branch rules unchanged. Enable them after the first default-branch CI run passes.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError, KeyError, OSError) as error:
        print(f"GitHub configuration failed: {error}", file=sys.stderr)
        sys.exit(2)
