"""Gemeinsame Hilfsfunktionen fuer die Spike-Skripte (nur Standardbibliothek).

Werte kommen aus Umgebungsvariablen, ersatzweise aus der .env im Repo-Wurzelordner.
Schluesselwerte werden nie ausgegeben; alle Texte von aussen laufen durch redact().
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BUILD_DIR = REPO_ROOT / "build"
LOG_DIR = BUILD_DIR / "logs"
PLACE_FILE = BUILD_DIR / "spike.rbxl"

SECRET_VARS = ("ROBLOX_CI_API_KEY", "ROBLOX_STAGING_API_KEY")
# Optionale Schluessel (nur lokal: Asset-Uploads, manueller Production-Publish); fehlen sie, ist das kein Fehler.
OPTIONAL_SECRET_VARS = ("ROBLOX_ASSETS_API_KEY", "ROBLOX_PRODUCTION_API_KEY")
TARGETS = {
    "ci": ("ROBLOX_CI_API_KEY", "ROBLOX_CI_UNIVERSE_ID", "ROBLOX_CI_PLACE_ID"),
    "staging": ("ROBLOX_STAGING_API_KEY", "ROBLOX_STAGING_UNIVERSE_ID", "ROBLOX_STAGING_PLACE_ID"),
}
# Production (Live-Spiel): nur manuell ueber publish.py --target production; IDs aus der committeten
# deploy/production.json (nicht geheim), Schluessel nur aus ROBLOX_PRODUCTION_API_KEY. Die CI kennt dieses Ziel nicht.
PRODUCTION_KEY_VAR = "ROBLOX_PRODUCTION_API_KEY"
PRODUCTION_FILE = REPO_ROOT / "deploy" / "production.json"

EXIT_INFRA = 2
EXIT_AUTH = 3

SCOPE_HINTS = {
    "publish": "universe-places:write",
    "luau-create": "universe.place.luau-execution-session:write",
    "luau-read": "universe.place.luau-execution-session:read",
}

_dotenv_cache: dict[str, str] | None = None


def _dotenv() -> dict[str, str]:
    global _dotenv_cache
    if _dotenv_cache is None:
        _dotenv_cache = {}
        path = REPO_ROOT / ".env"
        if path.is_file():
            for raw in path.read_text(encoding="utf-8-sig").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                name, value = line.split("=", 1)
                name = name.strip().removeprefix("export ").strip()
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                _dotenv_cache[name] = value
    return _dotenv_cache


def env(name: str) -> str:
    value = os.environ.get(name) or _dotenv().get(name)
    if not value:
        fail(f"Variable {name} fehlt (weder Umgebung noch .env).", EXIT_INFRA)
    return value


def secret_values() -> list[str]:
    values = []
    for name in SECRET_VARS:
        value = os.environ.get(name) or _dotenv().get(name)
        if value:
            values.append(value)
    return values


def optional_secret_values() -> list[str]:
    """Werte der OPTIONAL_SECRET_VARS, die in Umgebung oder .env gesetzt sind (fehlende werden ausgelassen)."""
    values = []
    for name in OPTIONAL_SECRET_VARS:
        value = os.environ.get(name) or _dotenv().get(name)
        if value:
            values.append(value)
    return values


def redact(text: str) -> str:
    for value in secret_values() + optional_secret_values():
        text = text.replace(value, "***REDACTED***")
    return text


def fail(message: str, code: int):
    print(redact(message), file=sys.stderr)
    sys.exit(code)


def production_ids(path: Path = PRODUCTION_FILE) -> tuple[str, str]:
    """(universeId, placeId) aus deploy/production.json; beide als positive ganze Zahlen geprueft."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        universe, place = str(int(data["universeId"])), str(int(data["placeId"]))
    except (OSError, ValueError, KeyError, TypeError) as err:
        fail(f"{path} fehlt oder ist ungueltig: {err}", EXIT_INFRA)
    if int(universe) <= 0 or int(place) <= 0:
        fail(f"{path}: IDs muessen positiv sein.", EXIT_INFRA)
    return universe, place


def target_config(target: str) -> tuple[str, str, str]:
    if target == "production":
        universe, place = production_ids()
        return env(PRODUCTION_KEY_VAR), universe, place
    key_var, universe_var, place_var = TARGETS[target]
    return env(key_var), env(universe_var), env(place_var)


def write_log(name: str, text: str) -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    path = LOG_DIR / name
    path.write_text(redact(text), encoding="utf-8")
    return path


def request(
    method: str,
    url: str,
    api_key: str,
    *,
    body: bytes | None = None,
    content_type: str | None = None,
    scope_hint: str,
    max_attempts: int = 6,
) -> dict:
    """HTTP-Aufruf mit 429/5xx-Backoff. 401/403 bricht sofort ab (Stopp-Regel)."""
    delay = 5.0
    for attempt in range(1, max_attempts + 1):
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("x-api-key", api_key)
        if content_type:
            req.add_header("Content-Type", content_type)
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read().decode("utf-8", "replace")
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as err:
            detail = redact(err.read().decode("utf-8", "replace")[:500])
            if err.code in (401, 403):
                fail(
                    f"STOPP: HTTP {err.code} bei {method} {url}\n"
                    f"Vermutlich fehlender Scope/Berechtigung: {SCOPE_HINTS[scope_hint]}\nAntwort: {detail}",
                    EXIT_AUTH,
                )
            # 409 "Server is busy" beim Publishing ist laut Antworttext voruebergehend.
            retryable = err.code == 429 or err.code >= 500 or (err.code == 409 and "busy" in detail.lower())
            if not retryable or attempt == max_attempts:
                fail(f"HTTP {err.code} bei {method} {url}\nAntwort: {detail}", EXIT_INFRA)
            retry_after = err.headers.get("retry-after")
            wait = float(retry_after) if retry_after and retry_after.isdigit() else delay
            print(f"HTTP {err.code}, neuer Versuch in {wait:.0f}s ({attempt}/{max_attempts})", file=sys.stderr)
            time.sleep(wait)
            delay = min(delay * 2, 60.0)
        except urllib.error.URLError as err:
            if attempt == max_attempts:
                fail(f"Netzwerkfehler bei {method} {url}: {err.reason}", EXIT_INFRA)
            time.sleep(delay)
            delay = min(delay * 2, 60.0)
    raise AssertionError("unreachable")
