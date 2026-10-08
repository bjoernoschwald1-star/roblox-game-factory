"""Laedt einen gebauten Place (Standard build/spike.rbxl) als neue Version in den Ziel-Place hoch und gibt NUR die
Versionsnummer aus. Mit --file laesst sich ein anderer Build waehlen, z. B. build/junkyard.rbxl fuer Staging.

--target production (Live-Spiel, nur manuell; die CI nutzt dieses Ziel nie) prueft vorher in dieser Reihenfolge und
bricht sonst mit Exit 4 ab:
  1. --confirm <kurzer Commit-Hash> ist angegeben (mindestens 7 Zeichen) und passt zu HEAD.
  2. Der Arbeitsbaum ist sauber (git status --porcelain leer; ignorierte Dateien zaehlen nicht).
  3. HEAD ist auf origin/spike/phase-0 gepusht (git ls-remote liefert genau diesen Commit).
  4. Der Workflow-Lauf "spike" fuer genau diesen Commit ist abgeschlossen und erfolgreich (gh run list).
Danach: Schluessel aus ROBLOX_PRODUCTION_API_KEY, IDs aus deploy/production.json, frischer Build aus
junkyard.project.json nach build/junkyard-production.rbxl (--file ist hier verboten), Upload, und ein Eintrag
"Datum | Commit | Place-Version" in deploy/production-log.md. Der Log-Eintrag muss danach committet werden.

Doku: https://create.roblox.com/docs/cloud/guides/usage-place-publishing
"""

from __future__ import annotations

import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path
from typing import Callable

from _common import BUILD_DIR, EXIT_INFRA, PLACE_FILE, REPO_ROOT, fail, request, target_config

EXIT_GUARD = 4
BRANCH = "spike/phase-0"
WORKFLOW = "spike.yml"
PRODUCTION_PROJECT = "junkyard.project.json"
PRODUCTION_BUILD = BUILD_DIR / "junkyard-production.rbxl"
PRODUCTION_LOG = REPO_ROOT / "deploy" / "production-log.md"
LOG_HEADER = "# Production-Log Junkyard Magnet\n\nDatum (UTC) | Commit | Place-Version\n"

Runner = Callable[[list[str]], str]


def run_command(args: list[str]) -> str:
    """Fuehrt einen Befehl im Repo aus und liefert stdout; Fehler -> Exit 2 (nicht als bestandene Pruefung werten)."""
    result = subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"Befehl fehlgeschlagen ({' '.join(args[:3])} ...): {result.stderr.strip()[:300]}", EXIT_INFRA)
    return result.stdout


def guard(ok: bool, message: str):
    if not ok:
        fail(f"STOPP (production): {message}", EXIT_GUARD)


def check_production(confirm: str | None, run: Runner = run_command) -> str:
    """Prueft die Schutzregeln; liefert den vollen HEAD-Hash oder bricht mit EXIT_GUARD ab."""
    head = run(["git", "rev-parse", "HEAD"]).strip()
    guard(confirm is not None and len(confirm) >= 7, "--confirm <kurzer Commit-Hash> fehlt (mindestens 7 Zeichen).")
    guard(head.startswith(str(confirm).lower()), f"--confirm {confirm} passt nicht zu HEAD {head[:7]}.")
    guard(run(["git", "status", "--porcelain"]).strip() == "", "Arbeitsbaum ist nicht sauber.")
    remote = run(["git", "ls-remote", "origin", f"refs/heads/{BRANCH}"]).split()
    guard(len(remote) >= 1 and remote[0] == head, f"HEAD ist nicht auf origin/{BRANCH} gepusht.")
    runs = json.loads(
        run(
            [
                "gh", "run", "list", "--workflow", WORKFLOW, "--branch", BRANCH, "--limit", "30",
                "--json", "headSha,status,conclusion",
            ]
        )
        or "[]"
    )
    matching = [r for r in runs if r.get("headSha") == head]
    guard(len(matching) > 0, f"Kein Workflow-Lauf {WORKFLOW} fuer {head[:7]} gefunden.")
    guard(
        any(r.get("status") == "completed" and r.get("conclusion") == "success" for r in matching),
        f"Workflow-Lauf {WORKFLOW} fuer {head[:7]} ist nicht erfolgreich abgeschlossen.",
    )
    return head


def build_production(run: Runner = run_command) -> Path:
    """Baut immer frisch aus junkyard.project.json in eine eigene Datei."""
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    if PRODUCTION_BUILD.exists():
        PRODUCTION_BUILD.unlink()
    run(["rojo", "build", PRODUCTION_PROJECT, "-o", str(PRODUCTION_BUILD.relative_to(REPO_ROOT))])
    if not PRODUCTION_BUILD.is_file():
        fail(f"{PRODUCTION_BUILD} wurde nicht erzeugt.", EXIT_INFRA)
    return PRODUCTION_BUILD


def append_log(head: str, version: int, log_file: Path | None = None, today: str | None = None):
    log_file = log_file or PRODUCTION_LOG
    date = today or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M")
    if not log_file.is_file():
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_bytes(LOG_HEADER.encode())
    with log_file.open("ab") as handle:
        handle.write(f"{date} | {head[:7]} | {version}\n".encode())


def publish(target: str, place_file: Path = PLACE_FILE) -> int:
    api_key, universe_id, place_id = target_config(target)
    if not place_file.is_file():
        fail(f"{place_file} fehlt - zuerst tools/spike/build.py ausfuehren.", EXIT_INFRA)
    url = f"https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?versionType=Published"
    result = request(
        "POST",
        url,
        api_key,
        body=place_file.read_bytes(),
        content_type="application/octet-stream",
        scope_hint="publish",
    )
    version = result.get("versionNumber")
    if not isinstance(version, int):
        fail(f"Unerwartete Antwort ohne versionNumber: {result}", EXIT_INFRA)
    return version


def publish_production(confirm: str | None, run: Runner = run_command) -> int:
    head = check_production(confirm, run)
    target_config("production")  # Schluessel und IDs vor dem Build pruefen (fehlt etwas: Exit 2)
    place_file = build_production(run)
    version = publish("production", place_file)
    append_log(head, version)
    return version


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("ci", "staging", "production"), required=True)
    parser.add_argument("--file", help="Place-Datei relativ zum Repo-Wurzelordner (Standard build/spike.rbxl)")
    parser.add_argument("--confirm", help="nur production: kurzer Hash von HEAD als Bestaetigung")
    args = parser.parse_args()
    if args.target == "production":
        guard(args.file is None, "--file ist fuer production nicht erlaubt (Build immer frisch).")
        print(publish_production(args.confirm))
        return 0
    place_file = (REPO_ROOT / args.file) if args.file else PLACE_FILE
    print(publish(args.target, place_file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
