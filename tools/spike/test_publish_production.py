"""Offline-Tests fuer das Production-Ziel von publish.py: Schutzregeln, Log-Eintrag, CI ohne Production.

Kein Netz, kein git/gh/rojo: Befehle laufen ueber einen Fake-Runner, Upload und Schluessel sind gemockt.
Ausfuehren: python -m unittest discover -s tools/spike -p "test_*.py"
"""

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import _common
import publish

HEAD = "c297150150a84990a0e912749ce734e949b30497"
OTHER = "32b5aa90f403da14ca1ac5d8362496aee8307787"
WORKFLOW_FILE = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "spike.yml"


def fake_runner(*, status="", remote=HEAD, runs=None, calls=None):
    runs = [{"headSha": HEAD, "status": "completed", "conclusion": "success"}] if runs is None else runs

    def run(args):
        if calls is not None:
            calls.append(args)
        if args[:2] == ["git", "rev-parse"]:
            return HEAD + "\n"
        if args[:2] == ["git", "status"]:
            return status
        if args[:2] == ["git", "ls-remote"]:
            return f"{remote}\trefs/heads/spike/phase-0\n" if remote else ""
        if args[:3] == ["gh", "run", "list"]:
            return json.dumps(runs)
        if args[0] == "rojo":
            Path(publish.PRODUCTION_BUILD).write_bytes(b"place")
            return ""
        raise AssertionError(f"unerwarteter Befehl {args}")

    return run


class ProductionGuardTest(unittest.TestCase):
    def expect_stop(self, confirm, runner, fragment):
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as stop:
            publish.check_production(confirm, runner)
        self.assertEqual(stop.exception.code, publish.EXIT_GUARD)
        self.assertIn(fragment, err.getvalue())

    def test_all_rules_met_returns_head(self):
        self.assertEqual(publish.check_production("c297150", fake_runner()), HEAD)

    def test_confirm_missing_or_wrong(self):
        self.expect_stop(None, fake_runner(), "--confirm")
        self.expect_stop("c29", fake_runner(), "--confirm")
        self.expect_stop("32b5aa9", fake_runner(), "passt nicht zu HEAD")

    def test_dirty_worktree_stops(self):
        self.expect_stop("c297150", fake_runner(status=" M core/x.luau\n"), "nicht sauber")

    def test_not_pushed_stops(self):
        self.expect_stop("c297150", fake_runner(remote=OTHER), "nicht auf origin/spike/phase-0")
        self.expect_stop("c297150", fake_runner(remote=""), "nicht auf origin/spike/phase-0")

    def test_ci_run_missing_or_not_successful_stops(self):
        self.expect_stop("c297150", fake_runner(runs=[]), "Kein Workflow-Lauf")
        other = [{"headSha": OTHER, "status": "completed", "conclusion": "success"}]
        self.expect_stop("c297150", fake_runner(runs=other), "Kein Workflow-Lauf")
        failed = [{"headSha": HEAD, "status": "completed", "conclusion": "failure"}]
        self.expect_stop("c297150", fake_runner(runs=failed), "nicht erfolgreich")
        running = [{"headSha": HEAD, "status": "in_progress", "conclusion": ""}]
        self.expect_stop("c297150", fake_runner(runs=running), "nicht erfolgreich")

    def test_happy_path_builds_fresh_publishes_and_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build = root / "build" / "junkyard-production.rbxl"
            build.parent.mkdir()
            build.write_bytes(b"alt")
            log = root / "deploy" / "production-log.md"
            calls = []
            with (
                mock.patch.object(publish, "PRODUCTION_BUILD", build),
                mock.patch.object(publish, "BUILD_DIR", build.parent),
                mock.patch.object(publish, "REPO_ROOT", root),
                mock.patch.object(publish, "PRODUCTION_LOG", log),
                mock.patch.object(publish, "target_config", return_value=("key", "1", "2")),
                mock.patch.object(publish, "publish", return_value=7) as upload,
            ):
                version = publish.publish_production("c297150", fake_runner(calls=calls))
            self.assertEqual(version, 7)
            upload.assert_called_once_with("production", build)
            self.assertEqual(build.read_bytes(), b"place")  # frisch gebaut, alte Datei ersetzt
            rojo = [c for c in calls if c[0] == "rojo"][0]
            self.assertEqual(rojo[:3], ["rojo", "build", "junkyard.project.json"])
            text = log.read_text(encoding="utf-8")
            self.assertTrue(text.startswith("# Production-Log"))
            self.assertRegex(text.splitlines()[-1], r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2} \| c297150 \| 7$")

    def test_guard_failure_never_uploads(self):
        with mock.patch.object(publish, "publish") as upload, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                publish.publish_production("c297150", fake_runner(status="?? neu.txt\n"))
        upload.assert_not_called()

    def test_production_ids_from_committed_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "production.json"
            good.write_text('{"universeId": 11, "placeId": 22}', encoding="utf-8")
            self.assertEqual(_common.production_ids(good), ("11", "22"))
            bad = Path(tmp) / "bad.json"
            bad.write_text('{"universeId": 11}', encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                _common.production_ids(bad)
        self.assertTrue(_common.PRODUCTION_FILE.is_file())
        data = json.loads(_common.PRODUCTION_FILE.read_text(encoding="utf-8"))
        self.assertEqual(sorted(data), ["placeId", "universeId"])


class WorkflowWithoutProductionTest(unittest.TestCase):
    def test_spike_workflow_never_uses_production(self):
        text = WORKFLOW_FILE.read_text(encoding="utf-8")
        self.assertNotIn("production", text.lower())
        self.assertNotIn("ROBLOX_PRODUCTION", text)


if __name__ == "__main__":
    unittest.main()
