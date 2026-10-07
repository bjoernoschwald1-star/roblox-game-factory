"""Offline-Tests fuer upload_models.py: gefaelschte Open-Cloud-Antworten, keine Netzaufrufe, keine .env.

Ausfuehren: python -m unittest discover -s tools/assets -p "test_*.py"
"""

import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path

import upload_models as um

KEY = "fake-key-123"


class FakeResponse:
    def __init__(self, payload: dict):
        self._raw = json.dumps(payload).encode()

    def read(self):
        return self._raw

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class FakeRoblox:
    """Antwortet je nach URL; moderation ist die Folge der Moderationszustaende je Asset."""

    def __init__(self, moderation=("Approved",), fail_status=None, op_polls=1):
        self.moderation = list(moderation)
        self.fail_status = fail_status
        self.op_polls = op_polls
        self.calls: list[tuple[str, str, dict]] = []
        self.next_asset = 1000
        self.pending: dict[str, int] = {}

    def urlopen(self, req, timeout=None):
        headers = dict(req.header_items())
        self.calls.append((req.get_method(), req.full_url, headers))
        if self.fail_status:
            raise urllib.error.HTTPError(req.full_url, self.fail_status, "x", {},
                                         io.BytesIO(f"denied for {KEY}".encode()))
        if req.get_method() == "POST":
            self.next_asset += 1
            op_id = f"op{self.next_asset}"
            self.pending[op_id] = self.op_polls
            return FakeResponse({"path": f"operations/{op_id}", "operationId": op_id, "done": False})
        if "/operations/" in req.full_url:
            op_id = req.full_url.rsplit("/", 1)[-1]
            self.pending[op_id] -= 1
            if self.pending[op_id] > 0:
                return FakeResponse({"path": f"operations/{op_id}", "done": False})
            return FakeResponse({"path": f"operations/{op_id}", "done": True,
                                 "response": {"assetId": op_id.removeprefix("op"), "assetType": "Model"}})
        state = self.moderation.pop(0) if len(self.moderation) > 1 else self.moderation[0]
        return FakeResponse({"assetId": "x", "moderationResult": {"moderationState": state}})


class UploadModelsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.lock = self.dir / "assets.lock.json"
        self.files = []
        for name in ("a.fbx", "b.fbx"):
            path = self.dir / name
            path.write_bytes(b"FBX-DATA")
            self.files.append(path)
        self.sleeps: list[float] = []

    def tearDown(self):
        self.tmp.cleanup()

    def client(self, fake):
        return um.Client(KEY, urlopen=fake.urlopen, sleep=self.sleeps.append)

    def test_upload_writes_lock_without_key(self):
        fake = FakeRoblox(moderation=("Reviewing", "Approved"), op_polls=2)
        code = um.run(self.files, self.client(fake), "42", self.lock)
        self.assertEqual(code, 0)
        text = self.lock.read_text(encoding="utf-8")
        self.assertNotIn(KEY, text)
        entries = json.loads(text)["assets"]
        self.assertEqual([e["file"] for e in entries], ["a.fbx", "b.fbx"])
        self.assertEqual(entries[0]["status"], "Approved")
        self.assertEqual(set(entries[0]), {"file", "assetId", "status"})
        post = next(c for c in fake.calls if c[0] == "POST")
        self.assertEqual(post[2]["X-api-key"], KEY)
        self.assertTrue(post[2]["Content-type"].startswith("multipart/form-data; boundary="))

    def test_multipart_contains_request_and_file(self):
        body, content_type = um.multipart({"assetType": "Model"}, "a.fbx", b"DATA", "BOUND")
        self.assertEqual(content_type, "multipart/form-data; boundary=BOUND")
        self.assertIn(b'name="request"', body)
        self.assertIn(b'name="fileContent"; filename="a.fbx"', body)
        self.assertIn(b"DATA", body)
        self.assertTrue(body.endswith(b"--BOUND--\r\n"))

    def test_auth_error_stops_immediately_and_redacts(self):
        fake = FakeRoblox(fail_status=403)
        with self.assertRaises(um.UploadStop) as ctx:
            um.run(self.files, self.client(fake), "42", self.lock)
        self.assertEqual(ctx.exception.code, um.EXIT_AUTH)
        self.assertNotIn(KEY, str(ctx.exception))
        self.assertEqual(len(fake.calls), 1)
        self.assertFalse(self.lock.exists())

    def test_rejected_stops_further_uploads_but_keeps_lock(self):
        fake = FakeRoblox(moderation=("Rejected",))
        with self.assertRaises(um.UploadStop) as ctx:
            um.run(self.files, self.client(fake), "42", self.lock)
        self.assertEqual(ctx.exception.code, um.EXIT_REJECTED)
        self.assertEqual(sum(1 for c in fake.calls if c[0] == "POST"), 1)
        entries = json.loads(self.lock.read_text(encoding="utf-8"))["assets"]
        self.assertEqual(entries, [{"file": "a.fbx", "assetId": "1001", "status": "Rejected"}])

    def test_moderation_timeout_reports_reviewing(self):
        fake = FakeRoblox(moderation=("Reviewing",))
        state = um.moderation_state(self.client(fake), "7", poll_seconds=1, max_polls=3)
        self.assertEqual(state, "Reviewing")
        self.assertEqual(self.sleeps, [1, 1])

    def test_server_error_retries_then_fails(self):
        fake = FakeRoblox(fail_status=503)
        with self.assertRaises(um.UploadStop) as ctx:
            self.client(fake).call("GET", "https://example.invalid/x", attempts=3)
        self.assertEqual(ctx.exception.code, um.EXIT_INFRA)
        self.assertEqual(len(fake.calls), 3)
        self.assertEqual(self.sleeps, [2.0, 4.0])

    def test_pilot_limit(self):
        with self.assertRaises(um.UploadStop):
            um.run(self.files * 7, self.client(FakeRoblox()), "42", self.lock)
        self.assertEqual(len(um.PILOT_FILES), 13)

    def test_missing_key_skips(self):
        with self.assertRaises(um.UploadStop) as ctx:
            um.load_config(environ={}, dotenv=dict)
        self.assertEqual(ctx.exception.code, um.EXIT_INFRA)
        self.assertIn("uebersprungen", str(ctx.exception))

    def test_lock_merges_existing_entries(self):
        self.lock.write_text(json.dumps({"assets": [{"file": "z.fbx", "assetId": "9", "status": "Approved"}]}),
                             encoding="utf-8")
        um.write_lock([{"file": "a.fbx", "assetId": "1", "status": "Reviewing", "extra": "x"}], self.lock)
        entries = json.loads(self.lock.read_text(encoding="utf-8"))["assets"]
        self.assertEqual([e["file"] for e in entries], ["a.fbx", "z.fbx"])
        self.assertNotIn("extra", entries[0])


if __name__ == "__main__":
    unittest.main()
