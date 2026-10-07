"""Rot/Gruen-Nachweis: "green" muss Exit 0 liefern, "red" Exit 1 (Tests fehlgeschlagen).
Zusaetzlich muss die Suite "core" (Tests der Core Engine) Exit 0 liefern.

Ein Infrastrukturfehler bei "red" (Exit 2/3) zaehlt bewusst NICHT als korrekt erkanntes Rot.
Pro Durchlauf entstehen genau drei Luau-Execution-Tasks (Limit: 5 pro Minute pro Key-Besitzer);
ein 429 wird in _common.request mit Backoff wiederholt.
"""

import subprocess
import sys
from pathlib import Path

from _common import redact, write_log
from publish import publish

HERE = Path(__file__).resolve().parent


def run_suite(suite: str, version: int) -> int:
    proc = subprocess.run(
        [sys.executable, str(HERE / "run_tests.py"), "--suite", suite, "--version", str(version)],
        capture_output=True,
        text=True,
    )
    output = redact(proc.stdout + proc.stderr)
    print(output)
    write_log(f"selfcheck_{suite}.log", output + f"\nexit={proc.returncode}\n")
    print(f"selfcheck: suite={suite} exit={proc.returncode}")
    return proc.returncode


def main() -> int:
    version = publish("ci")
    print(f"selfcheck: CI place version {version}")
    green = run_suite("green", version)
    red = run_suite("red", version)
    core = run_suite("core", version)
    ok = green == 0 and red == 1 and core == 0
    print(
        f"selfcheck: green={'PASS' if green == 0 else 'FAIL'} red={'DETECTED' if red == 1 else 'NOT DETECTED'}"
        f" core={'PASS' if core == 0 else 'FAIL'}"
    )
    print(f"selfcheck: {'OK' if ok else 'FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
