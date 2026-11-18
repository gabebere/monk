import importlib.util
import json
from pathlib import Path
import re
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "configure_github.py"
SPEC = importlib.util.spec_from_file_location("configure_github", SCRIPT)
github = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(github)


class RepositoryConfigurationTests(unittest.TestCase):
    def test_required_checks_match_the_checked_in_ci_job_names(self):
        workflow = (github.ROOT / ".github" / "workflows" / "apple-ci.yml").read_text()
        jobs = set(re.findall(r"^    name: (.+)$", workflow, re.MULTILINE))
        self.assertEqual(github.required_checks(github.load_manifest(github.DEFAULT_MANIFEST)), jobs)

    def test_new_failed_attempt_does_not_reuse_an_older_pass(self):
        checks = [
            {"id": 1, "name": "Mac", "status": "completed", "conclusion": "success"},
            {"id": 2, "name": "Mac", "status": "completed", "conclusion": "failure"},
        ]
        self.assertFalse(github.latest_checks_passed(checks, {"Mac"}))

    def test_missing_or_in_progress_checks_prevent_activation(self):
        checks = [{"id": 1, "name": "Mac", "status": "in_progress", "conclusion": None}]
        self.assertFalse(github.latest_checks_passed(checks, {"Mac"}))
        self.assertFalse(github.latest_checks_passed(checks, {"iOS"}))
        self.assertFalse(github.latest_checks_passed([], set()))

    def test_unrelated_checks_do_not_prevent_all_required_successes(self):
        checks = [
            {"id": 1, "name": "Mac", "status": "completed", "conclusion": "success"},
            {"id": 2, "name": "Other", "status": "completed", "conclusion": "failure"},
        ]
        self.assertTrue(github.latest_checks_passed(checks, {"Mac"}))

    def test_default_command_is_offline_and_does_not_mutate_github(self):
        with patch.object(github, "api") as api, patch("builtins.print"):
            self.assertEqual(github.main([]), 0)
        api.assert_not_called()

    def test_failed_ci_preflight_blocks_all_mutations(self):
        manifest = github.load_manifest(github.DEFAULT_MANIFEST)
        base = "repos/" + manifest["repository"]
        def response(path, method="GET", payload=None):
            self.assertEqual(method, "GET", "No write may precede the CI guard")
            if path == base:
                return {"permissions": {"admin": True}, "default_branch": "main"}
            if "/rulesets" in path:
                return []
            if "/branches/" in path:
                return {"commit": {"sha": "abc"}}
            return {"check_runs": []}
        with patch.object(github, "api", side_effect=response), patch("builtins.print"):
            with self.assertRaisesRegex(RuntimeError, "nothing was changed"):
                github.main(["--apply", "--activate-rules"])

    def test_ordinary_apply_never_creates_or_changes_rulesets(self):
        calls = []
        manifest = github.load_manifest(github.DEFAULT_MANIFEST)
        def response(path, method="GET", payload=None):
            calls.append((path, method))
            if method != "GET":
                return {}
            if "/rulesets" in path:
                return []
            return {"permissions": {"admin": True}, "default_branch": "main"}
        with patch.object(github, "api", side_effect=response), patch("builtins.print"):
            self.assertEqual(github.main(["--apply"]), 0)
        self.assertIn(("repos/" + manifest["repository"], "PATCH"), calls)
        self.assertFalse(any("rulesets" in path and method != "GET" for path, method in calls))

    def test_ruleset_comparison_ignores_order_and_server_metadata(self):
        desired = github.load_manifest(github.DEFAULT_MANIFEST)["ruleset"]
        actual = json.loads(json.dumps(desired))
        actual["id"] = 123
        actual["rules"].reverse()
        self.assertEqual(github.normalize_ruleset(actual), github.normalize_ruleset(desired))

    def test_ruleset_comparison_accepts_api_defaults_but_detects_extra_checks(self):
        desired = github.load_manifest(github.DEFAULT_MANIFEST)["ruleset"]
        actual = json.loads(json.dumps(desired))
        status_rule = next(rule for rule in actual["rules"] if rule["type"] == "required_status_checks")
        status_rule["parameters"]["do_not_enforce_on_create"] = False
        for check in status_rule["parameters"]["required_status_checks"]:
            check["integration_id"] = None
        self.assertTrue(github.rulesets_equal(actual, desired))
        status_rule["parameters"]["required_status_checks"].append({"context": "Unexpected check"})
        self.assertFalse(github.rulesets_equal(actual, desired))


if __name__ == "__main__":
    unittest.main()
