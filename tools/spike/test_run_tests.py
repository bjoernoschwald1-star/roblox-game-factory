"""Offline-Tests fuer run_tests.py: gefaelschte Roblox-Antworten, injizierte Uhr, kein Netz, keine .env.

Ausfuehren: python -m unittest discover -s tools/spike -p "test_*.py"
"""

import contextlib
import io
import json
import re
import unittest
import urllib.error
from unittest import mock

import _common
import run_tests

SCRIPT_RE = re.compile(r'Main\("(\w+)", "(\w+)"\)')
VERSION = 7


class FakeClock:
    def __init__(self):
        self.now = 0.0
        self.sleeps: list[float] = []

    def clock(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds


class FakeRoblox:
    """Beantwortet die Luau-Execution-Aufrufe. behaviours legt je erstellter Task das Verhalten fest:
    "pass" (bestanden), "fail" (Tests fehlgeschlagen), "hang" (bleibt PROCESSING), "error" (Roblox-Fehler)."""

    def __init__(self, clock: FakeClock, behaviours: list[str]):
        self.clock = clock
        self.behaviours = behaviours
        self.created: list[dict] = []
        self.events: list[tuple[str, str]] = []

    def request(self, method, url, api_key, *, body=None, content_type=None, scope_hint, **_):
        if method == "POST":
            n = len(self.created) + 1
            suite, run_id = SCRIPT_RE.search(json.loads(body)["script"]).groups()
            path = f"universes/1/places/2/versions/{VERSION}/luau-execution-sessions/session{n}/tasks/task{n}-id"
            self.created.append(
                {"at": self.clock.now, "url": url, "path": path, "suite": suite, "run_id": run_id,
                 "behaviour": self.behaviours[n - 1]}
            )
            self.events.append(("create", path))
            return {"path": path, "state": "QUEUED"}

        task = next(t for t in self.created if t["path"] in url)
        if "/logs?" in url:
            self.events.append(("logs", task["path"]))
            return {"luauExecutionSessionTaskLogs": [{"structuredMessages": self._messages(task)}]}
        self.events.append(("poll", task["path"]))
        return self._state(task)

    @staticmethod
    def _state(task: dict) -> dict:
        behaviour, path = task["behaviour"], task["path"]
        if behaviour == "hang":
            return {"path": path, "state": "PROCESSING"}
        if behaviour == "pass":
            return {"path": path, "state": "COMPLETE", "output": {"results": [{"passed": 2, "failed": 0}]}}
        if behaviour == "fail":
            return {"path": path, "state": "FAILED", "error": {"code": "SCRIPT_ERROR", "message": "1 of 3 failed"}}
        return {"path": path, "state": "FAILED", "error": {"code": "INTERNAL_ERROR", "message": "internal error"}}

    @staticmethod
    def _messages(task: dict) -> list[dict]:
        counts = {"pass": (2, 0, 2), "fail": (2, 1, 3)}.get(task["behaviour"])
        if counts is None:
            return []
        passed, failed, total = counts
        line = (
            f"[spike] SUMMARY suite={task['suite']} run={task['run_id']} "
            f"passed={passed} failed={failed} total={total}"
        )
        return [{"createTime": "2026-01-01T00:00:00Z", "messageType": "OUTPUT", "message": line}]


class FakeResponse:
    def __init__(self, payload: dict):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self) -> bytes:
        return json.dumps(self.payload).encode()


def http_error(code: int) -> urllib.error.HTTPError:
    return urllib.error.HTTPError("https://apis.roblox.com/x", code, "denied", {}, io.BytesIO(b"{}"))


class RunTestsTest(unittest.TestCase):
    def setUp(self):
        # Keine echten Zugangsdaten, keine Logdateien, keine .env.
        for patcher in (
            mock.patch.object(run_tests, "target_config", lambda target: ("test-key", "1", "2")),
            mock.patch.object(run_tests, "write_log", lambda name, text: None),
            mock.patch.object(_common, "secret_values", lambda: []),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def run_suite(self, behaviours: list[str], suite: str = "green"):
        clock = FakeClock()
        fake = FakeRoblox(clock, behaviours)
        out = io.StringIO()
        with (
            mock.patch.object(run_tests, "request", fake.request),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
        ):
            code = run_tests.run(suite, VERSION, clock=clock.clock, sleep=clock.sleep)
        return code, fake, clock, out.getvalue()

    def test_a_pass_creates_one_task(self):
        code, fake, _, _ = self.run_suite(["pass"])
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.created), 1)

    def test_b_failed_tests_are_not_retried(self):
        code, fake, _, _ = self.run_suite(["fail"], suite="red")
        self.assertEqual(code, 1)
        self.assertEqual(len(fake.created), 1)

    def test_c_hung_task_is_replaced_once(self):
        code, fake, clock, out = self.run_suite(["hang", "pass"])
        self.assertEqual(code, 0)
        self.assertEqual(len(fake.created), 2)
        self.assertIn("[spike] task task1-id hung (state=PROCESSING), retrying once", out)
        first, second = fake.created
        self.assertEqual(second["suite"], first["suite"])
        self.assertIn(f"/versions/{VERSION}/", second["url"])
        self.assertNotEqual(second["run_id"], first["run_id"])
        # Wartezeit: Zeitlimit + 60 s, danach wird die alte Task nicht mehr abgefragt.
        self.assertGreaterEqual(second["at"] - first["at"], run_tests.TASK_TIMEOUT_S + 60)
        retry_index = fake.events.index(("create", second["path"]))
        self.assertNotIn(first["path"], [path for _, path in fake.events[retry_index:]])

    def test_d_both_hung_gives_infra_exit(self):
        code, fake, _, out = self.run_suite(["hang", "hang"])
        self.assertEqual(code, 2)
        self.assertEqual(len(fake.created), 2)
        self.assertIn("task1-id", out)
        self.assertIn("task2-id", out)

    def test_e_roblox_error_state_is_not_retried(self):
        code, fake, _, out = self.run_suite(["error"])
        self.assertEqual(code, 2)
        self.assertEqual(len(fake.created), 1)
        self.assertNotIn("retrying", out)

    def test_f_auth_errors_exit_3_without_retry(self):
        clock = FakeClock()
        out = io.StringIO()

        # 401 schon beim Erstellen der Task.
        with (
            mock.patch.object(_common.urllib.request, "urlopen", side_effect=http_error(401)) as urlopen,
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
            self.assertRaises(SystemExit) as raised,
        ):
            run_tests.run("green", VERSION, clock=clock.clock, sleep=clock.sleep)
        self.assertEqual(raised.exception.code, 3)
        self.assertEqual(urlopen.call_count, 1)

        # 403 bei der Statusabfrage nach erfolgreichem Erstellen.
        created = FakeResponse({"path": "universes/1/places/2/versions/7/luau-execution-sessions/s/tasks/t"})
        with (
            mock.patch.object(_common.urllib.request, "urlopen", side_effect=[created, http_error(403)]) as urlopen,
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
            self.assertRaises(SystemExit) as raised,
        ):
            run_tests.run("green", VERSION, clock=clock.clock, sleep=clock.sleep)
        self.assertEqual(raised.exception.code, 3)
        self.assertEqual(urlopen.call_count, 2)
        self.assertEqual([c.args[0].get_method() for c in urlopen.call_args_list], ["POST", "GET"])

    def test_g_task_creations_are_at_least_13_seconds_apart(self):
        clock = FakeClock()
        throttle = run_tests.CreateThrottle(clock.clock, clock.sleep)
        throttle.wait()
        first = clock.now
        throttle.wait()
        self.assertGreaterEqual(clock.now - first, 13)

        # Auch innerhalb eines Laufs: haengt die erste Task kuerzer als 13 s, wartet die Wiederholung.
        with mock.patch.object(run_tests, "POLL_DEADLINE_S", 1):
            code, fake, clock, _ = self.run_suite(["hang", "pass"])
        self.assertEqual(code, 0)
        self.assertGreaterEqual(fake.created[1]["at"] - fake.created[0]["at"], 13)
        self.assertIn(11.0, clock.sleeps)


if __name__ == "__main__":
    unittest.main()
