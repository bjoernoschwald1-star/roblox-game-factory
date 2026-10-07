"""Fuehrt eine Testsuite per Open Cloud Luau Execution im CI-Place aus.

Exit-Codes: 0 = alle Tests bestanden, 1 = Tests fehlgeschlagen,
2 = Infrastruktur-/Ablauffehler, 3 = 401/403 (Stopp-Regel).
Doku: https://create.roblox.com/docs/cloud/reference/features/luau-execution
"""

import argparse
import json
import re
import secrets
import sys
import time

from _common import EXIT_INFRA, fail, request, target_config, write_log
from publish import publish

API = "https://apis.roblox.com/cloud/v2"
TASK_TIMEOUT = "180s"
POLL_DEADLINE_S = 420
SUMMARY_RE = re.compile(r"\[spike\] SUMMARY suite=(\w+) run=(\w+) passed=(\d+) failed=(\d+) total=(\d+)")

ENTRY_SCRIPT = """\
local Spike = game:GetService("ServerScriptService"):WaitForChild("Spike")
local Main = require(Spike:WaitForChild("Main"))
return Main("{suite}", "{run_id}")
"""


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


def run(suite: str, version: int | None) -> int:
    api_key, universe_id, place_id = target_config("ci")
    if version is None:
        version = publish("ci")
    run_id = f"{int(time.time())}_{secrets.token_hex(4)}"
    print(f"suite={suite} place_version={version} run_id={run_id}")

    task = request(
        "POST",
        f"{API}/universes/{universe_id}/places/{place_id}/versions/{version}/luau-execution-session-tasks",
        api_key,
        body=json.dumps({"script": ENTRY_SCRIPT.format(suite=suite, run_id=run_id), "timeout": TASK_TIMEOUT}).encode(),
        content_type="application/json",
        scope_hint="luau-create",
    )
    task_path = task["path"]
    print(f"task={task_path}")

    # Status mit Backoff abfragen (Limit: 200 GET/min pro Key-Besitzer).
    delay, deadline = 2.0, time.monotonic() + POLL_DEADLINE_S
    while task.get("state") not in ("COMPLETE", "FAILED", "CANCELLED"):
        if time.monotonic() > deadline:
            fail(f"Task {task_path} nach {POLL_DEADLINE_S}s nicht beendet (state={task.get('state')}).", EXIT_INFRA)
        time.sleep(delay)
        delay = min(delay * 1.5, 15.0)
        task = request("GET", f"{API}/{task_path}", api_key, scope_hint="luau-read")
    state = task["state"]

    # Logs koennen kurz nachlaufen: bis zu drei Versuche, bis die Zusammenfassung da ist.
    logs: list[str] = []
    for attempt in range(3):
        logs = fetch_logs(api_key, task_path)
        if any(SUMMARY_RE.search(line) for line in logs) or attempt == 2:
            break
        time.sleep(5)

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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("green", "red", "core"), required=True)
    parser.add_argument("--version", type=int, help="vorhandene Place-Version nutzen statt neu zu publizieren")
    args = parser.parse_args()
    return run(args.suite, args.version)


if __name__ == "__main__":
    sys.exit(main())
