"""Offline-Tests fuer check_secrets.py: temporaerer Ordner, erfundene Testwerte, keine .env, kein Netz.

Ausfuehren: python -m unittest discover -s tools/spike -p "test_*.py"
"""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_secrets

# Erfundene Werte (mindestens 16 Zeichen), absichtlich ohne Aehnlichkeit zu echten Schluesselformaten.
REQUIRED = ["testwert-pflicht-eins-0001", "testwert-pflicht-zwei-0002"]
OPTIONAL = "testwert-optional-asset-0003"
SHORT_OPTIONAL = "kurz-0004"
PRODUCTION = "testwert-optional-production-0005"


class CheckSecretsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "clean.txt").write_text("nichts zu sehen", encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def run_main(self, optional: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(check_secrets, "REPO_ROOT", self.root),
            mock.patch.object(check_secrets, "SKIP", (self.root / ".env", self.root / ".git")),
            mock.patch.object(check_secrets, "secret_values", return_value=list(REQUIRED)),
            mock.patch.object(check_secrets, "optional_secret_values", return_value=list(optional)),
            mock.patch.object(check_secrets.sys, "argv", ["check_secrets.py"]),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            code = check_secrets.main()
        return code, out.getvalue(), err.getvalue()

    def assert_no_values(self, *texts: str):
        for text in texts:
            for value in REQUIRED + [OPTIONAL, SHORT_OPTIONAL]:
                self.assertNotIn(value, text)

    def test_scan_finds_value_and_clean_folder_has_no_hit(self):
        hits, scanned = check_secrets.scan([self.root], [REQUIRED[0].encode()])
        self.assertEqual((hits, scanned), ([], 1))
        leak = self.root / "sub" / "leak.log"
        leak.parent.mkdir()
        leak.write_text(f"x={REQUIRED[0]}", encoding="utf-8")
        hits, scanned = check_secrets.scan([self.root], [REQUIRED[0].encode()])
        self.assertEqual((hits, scanned), ([leak], 2))

    def test_optional_value_found_in_assets_lock(self):
        lock = self.root / "games" / "x" / "art" / "assets.lock.json"
        lock.parent.mkdir(parents=True)
        lock.write_text('{"assets": [], "note": "' + OPTIONAL + '"}', encoding="utf-8")
        code, out, err = self.run_main([OPTIONAL])
        self.assertEqual(code, 1)
        self.assertIn(f"FUND: Schluesselwert in {lock}", out)
        self.assertIn("(optional: 1 von 2)", out)
        self.assert_no_values(out, err)

    def test_missing_optional_is_no_error(self):
        (self.root / "assets.lock.json").write_text(OPTIONAL, encoding="utf-8")
        code, out, err = self.run_main([])
        self.assertEqual(code, 0)
        self.assertIn("check_secrets: 2 Dateien geprueft, 0 Funde (optional: 0 von 2)", out)
        self.assert_no_values(out, err)

    def test_short_optional_value_is_ignored(self):
        (self.root / "note.txt").write_text(f"enthaelt {SHORT_OPTIONAL}", encoding="utf-8")
        self.assertEqual(check_secrets.usable_optional([SHORT_OPTIONAL, "", OPTIONAL]), [OPTIONAL])
        code, out, err = self.run_main([SHORT_OPTIONAL])
        self.assertEqual(code, 0)
        self.assertIn("(optional: 0 von 2)", out)
        self.assert_no_values(out, err)

    def test_missing_required_still_exit_2(self):
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.object(check_secrets, "secret_values", return_value=[REQUIRED[0]]),
            mock.patch.object(check_secrets, "optional_secret_values", return_value=[OPTIONAL]),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
        ):
            self.assertEqual(check_secrets.main(), 2)
        self.assert_no_values(out.getvalue(), err.getvalue())

    def test_env_and_git_are_skipped(self):
        (self.root / ".env").write_text(REQUIRED[0], encoding="utf-8")
        (self.root / ".git").mkdir()
        (self.root / ".git" / "config").write_text(REQUIRED[1], encoding="utf-8")
        code, out, err = self.run_main([OPTIONAL])
        self.assertEqual(code, 0)
        self.assertIn("check_secrets: 1 Dateien geprueft, 0 Funde (optional: 1 von 2)", out)
        self.assert_no_values(out, err)


    def test_production_key_is_optional_and_searched(self):
        self.assertIn("ROBLOX_PRODUCTION_API_KEY", check_secrets.OPTIONAL_SECRET_VARS)
        leak = self.root / "deploy" / "production-log.md"
        leak.parent.mkdir()
        leak.write_text(f"key {PRODUCTION}", encoding="utf-8")
        code, out, err = self.run_main([OPTIONAL, PRODUCTION])
        self.assertEqual(code, 1)
        self.assertIn(f"FUND: Schluesselwert in {leak}", out)
        self.assertIn("(optional: 2 von 2)", out)
        self.assertNotIn(PRODUCTION, out + err)
        leak.unlink()
        code, out, err = self.run_main([OPTIONAL])
        self.assertEqual(code, 0)
        self.assertIn("(optional: 1 von 2)", out)

if __name__ == "__main__":
    unittest.main()
