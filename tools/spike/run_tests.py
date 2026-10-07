"""Fuehrt eine Testsuite per Open Cloud Luau Execution im CI-Place aus.

Exit-Codes: 0 = alle Tests bestanden, 1 = Tests fehlgeschlagen,
2 = Infrastruktur-/Ablauffehler, 3 = 401/403 (Stopp-Regel).

Haengende Tasks: Erreicht eine Task nach TASK_TIMEOUT_S + HANG_GRACE_S keinen Endzustand, wird sie genau
einmal durch eine neue Task fuer dieselbe Suite auf derselben Place-Version ersetzt (mit neuer Lauf-ID);
die alte Task wird nicht weiter abgefragt. Ein Testergebnis (Exit 0/1), ein Roblox-Fehlerzustand und
401/403 werden nie wiederholt. Zwischen zwei Task-Erstellungen liegen mindestens MIN_CREATE_INTERVAL_S.
Doku: https://create.roblox.com/docs/cloud/reference/features/luau-execution
"""

from __future__ import annotations

import argparse
import json
import re
import secrets
import sys
import time
from typing import Callable

from _common import EXIT_INFRA, request, target_config, write_log
from publish import publish

API = "https://apis.roblox.com/cloud/v2"
TASK_TIMEOUT_S = 180
HANG_GRACE_S = 60
POLL_DEADLINE_S = TASK_TIMEOUT_S + HANG_GRACE_S
# Limit: 5 Task-Erstellungen pro Minute pro Key-Besitzer.
MIN_CREATE_INTERVAL_S = 13.0
TERMINAL_STATES = ("COMPLETE", "FAILED", "CANCELLED")
SUMMARY_RE = re.compile(r"\[spike\] SUMMARY suite=(\w+) run=(\w+) passed=(\d+) failed=(\d+) total=(\d+)")

ENTRY_SCRIPT = """\
local Spike = game:GetService("ServerScriptService"):WaitForChild("Spike")
local Main = require(Spike:WaitForChild("Main"))
return Main("{suite}", "{run_id}")
"""

Clock = Callable[[], float]
Sleep = Callable[[float], None]


class CreateThrottle:
    """Haelt zwischen zwei Task-Erstellungen mindestens min_interval Sekunden Abstand."""

    def __init__(self, clock: Clock, sleep: Sleep, min_interval: float = MIN_CREATE_INTERVAL_S):
        self.clock = clock
        self.sleep = sleep
        self.min_interval = min_interval
        self._last: float | None = None

    def wait(self) -> None:
        if self._last is not None:
            remaining = self._last + self.min_interval - self.clock()
            if remaining > 0:
                self.sleep(remaining)
        self._last = self.clock()


def task_id(task_path: str) -> str:
    return task_path.rsplit("/", 1)[-1]


def fetch_logs(api_key: str, task_path: str) -> list[str]:
    lines: list[str] = []
    page_token = ""
    while True:
        url = f"{API}/{task_path}/logs?maxPageSize=10000&view=STRUCTURED"
        if page_token:
            url += f"&pageToken={page_token}"
        page = request("GET", url, api_key, scope_hint="luau-read")
        for entry in page.get("luauExecutionSessionTaskLogs", []):
            for msg in entry.get("structuredMessages", []):
                lines.append(f"{msg.get('createTime', '')} {msg.get('messageType', '')}: {msg.get('message', '')}")
        page_token = page.get("nextPageToken") or ""
        if not page_token:
            return lines


def create_task(api_key: str, universe_id: str, place_id: str, version: int, suite: str, run_id: str) -> dict:
    return request(
        "POST",
        f"{API}/universes/{universe_id}/places/{place_id}/versions/{version}/luau-execution-session-tasks",
        api_key,
        body=json.dumps(
            {"script": ENTRY_SCRIPT.format(suite=suite, run_id=run_id), "timeout": f"{TASK_TIMEOUT_S}s"}
        ).encode(),
        content_type="application/json",
        scope_hint="luau-create",
    )


def wait_for_task(api_key: str, task: dict, clock: Clock, sleep: Sleep) -> dict:
    """Fragt den Status mit Backoff ab (Limit: 200 GET/min pro Key-Besitzer), bis ein Endzustand erreicht
    oder POLL_DEADLINE_S verstrichen ist. Liefert den zuletzt gesehenen Stand."""
    delay, deadline = 2.0, clock() + POLL_DEADLINE_S
    while task.get("state") not in TERMINAL_STATES:
        if clock() > deadline:
            return task
        sleep(delay)
        delay = min(delay * 1.5, 15.0)
        task = request("GET", f"{API}/{task['path']}", api_key, scope_hint="luau-read")
    return task


def evaluate(api_key: str, suite: str, run_id: str, task: dict, sleep: Sleep) -> int:
    task_path, state = task["path"], task["state"]

    # Logs koennen kurz nachlaufen: bis zu drei Versuche, bis die Zusammenfassung da ist.
    logs: list[str] = []
    for attempt in range(3):
        logs = fetch_logs(api_key, task_path)
        if any(SUMMARY_RE.search(line) for line in logs) or attempt == 2:
            break
        sleep(5)

    log_name = f"task_{suite}_{run_id}"
    write_log(f"{log_name}.json", json.dumps(task, indent=2))
    write_log(f"{log_name}.log", "\n".join(logs) + "\n")

    print(f"state={state}")
    if task.get("error"):
        print(f"error.code={task['error'].get('code')} error.message={task['error'].get('message')}")
    if task.get("output"):
        print(f"output.results={json.dumps(task['output'].get('results'))}")
    print("--- logs ---")
    for line in logs:
        print(line)
    print("--- end logs ---")

    summary = next((m for m in (SUMMARY_RE.search(line) for line in logs) if m), None)
    if summary is None or summary.group(2) != run_id:
        print("Keine Testzusammenfassung fuer diesen Lauf in den Logs gefunden.", file=sys.stderr)
        return EXIT_INFRA
    failed = int(summary.group(4))
    if state == "COMPLETE" and failed == 0:
        return 0
    if state == "FAILED" and task.get("error", {}).get("code") == "SCRIPT_ERROR" and failed > 0:
        return 1
    print(f"Inkonsistenter Zustand: state={state}, failed={failed}", file=sys.stderr)
    return EXIT_INFRA


def run(
    suite: str,
    version: int | None,
    *,
    clock: Clock = time.monotonic,
    sleep: Sleep = time.sleep,
    throttle: CreateThrottle | None = None,
) -> int:
    api_key, universe_id, place_id = target_config("ci")
    if version is None:
        version = publish("ci")
    throttle = throttle or CreateThrottle(clock, sleep)

    hung: list[str] = []
    for attempt in (1, 2):
        run_id = f"{int(time.time())}_{secrets.token_hex(4)}"
        print(f"suite={suite} place_version={version} run_id={run_id}")
        throttle.wait()
        task = create_task(api_key, universe_id, place_id, version, suite, run_id)
        print(f"task={task['path']}")

        task = wait_for_task(api_key, task, clock, sleep)
        if task.get("state") in TERMINAL_STATES:
            return evaluate(api_key, suite, run_id, task, sleep)

        hung.append(task_id(task["path"]))
        if attempt == 1:
            # Nur "Endzustand nicht erreicht" wird wiederholt; die alte Task wird nicht weiter abgefragt.
            print(f"[spike] task {hung[-1]} hung (state={task.get('state')}), retrying once")
        else:
            print(f"[spike] task {hung[-1]} hung (state={task.get('state')}), giving up")

    print(f"Tasks {', '.join(hung)} nach je {POLL_DEADLINE_S}s nicht beendet.", file=sys.stderr)
    return EXIT_INFRA


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("green", "red", "core"), required=True)
    parser.add_argument("--version", type=int, help="vorhandene Place-Version nutzen statt neu zu publizieren")
    args = parser.parse_args()
    return run(args.suite, args.version)


if __name__ == "__main__":
    sys.exit(main())
