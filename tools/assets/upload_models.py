"""Laedt Modelle (.fbx) ueber die Open Cloud Assets API hoch und schreibt das Ergebnis in eine Lock-Datei.

Ablauf je Datei: POST /assets/v1/assets (multipart) -> Operation pollen -> Moderationsstatus lesen ->
Eintrag (Dateiname, Asset-ID, Status) in games/junkyard_magnet/art/assets.lock.json.
Schluessel: ROBLOX_ASSETS_API_KEY und ROBLOX_ASSETS_CREATOR_USER_ID aus der Umgebung bzw. .env (gleiche
Lade-Logik wie tools/spike/_common.py). Schluesselwerte werden nie ausgegeben oder gespeichert.
Stopp-Regeln: 401/403 -> sofort Abbruch (Exit 3); Moderation lehnt ab -> keine weiteren Uploads (Exit 4).
Doku: https://create.roblox.com/docs/cloud/guides/usage-assets

Aufruf: python tools/assets/upload_models.py            (Pilot-Auswahl, hoechstens 13 Dateien)
        python tools/assets/upload_models.py a.fbx b.fbx
Offene Punkte: Moderation kann laenger als das Warte-Limit dauern; dann bleibt der Status "Reviewing".
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ART_DIR = REPO_ROOT / "games" / "junkyard_magnet" / "art"
EXPORT_DIR = ART_DIR / "export"
LOCK_FILE = ART_DIR / "assets.lock.json"

API = "https://apis.roblox.com/assets/v1"
KEY_VAR = "ROBLOX_ASSETS_API_KEY"
CREATOR_VAR = "ROBLOX_ASSETS_CREATOR_USER_ID"
MAX_UPLOADS = 13
MAX_BYTES = 20 * 1024 * 1024

PILOT_FILES = [
    *(f"item_{shape}_{rarity}.fbx" for shape in ("plate", "pipe", "gear", "bolt", "barrel") for rarity in ("rusty", "gold")),
    "tool_magnet.fbx",
    "prop_scrap_pile.fbx",
    "prop_container.fbx",
]

EXIT_INFRA = 2
EXIT_AUTH = 3
EXIT_REJECTED = 4


class UploadStop(Exception):
    def __init__(self, message: str, code: int):
        super().__init__(message)
        self.code = code


def _dotenv() -> dict[str, str]:
    values: dict[str, str] = {}
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
            values[name] = value
    return values


def load_config(environ=os.environ, dotenv=_dotenv) -> tuple[str, str]:
    file_values = dotenv()
    key = environ.get(KEY_VAR) or file_values.get(KEY_VAR)
    creator = environ.get(CREATOR_VAR) or file_values.get(CREATOR_VAR)
    if not key:
        raise UploadStop(f"{KEY_VAR} fehlt (weder Umgebung noch .env) - Upload uebersprungen.", EXIT_INFRA)
    if not creator:
        raise UploadStop(f"{CREATOR_VAR} fehlt (weder Umgebung noch .env).", EXIT_INFRA)
    return key, creator


class Client:
    """HTTP-Zugriff mit injizierbarem urlopen und Uhr; schwaerzt den Schluessel in allen Texten."""

    def __init__(self, api_key: str, urlopen=urllib.request.urlopen, sleep=time.sleep):
        self._key = api_key
        self._urlopen = urlopen
        self._sleep = sleep

    def redact(self, text: str) -> str:
        return text.replace(self._key, "***REDACTED***") if self._key else text

    def call(self, method: str, url: str, body: bytes | None = None, content_type: str | None = None,
             attempts: int = 5) -> dict:
        delay = 2.0
        for attempt in range(1, attempts + 1):
            req = urllib.request.Request(url, data=body, method=method)
            req.add_header("x-api-key", self._key)
            if content_type:
                req.add_header("Content-Type", content_type)
            try:
                with self._urlopen(req, timeout=120) as resp:
                    raw = resp.read().decode("utf-8", "replace")
                    return json.loads(raw) if raw.strip() else {}
            except urllib.error.HTTPError as err:
                detail = self.redact(err.read().decode("utf-8", "replace")[:500])
                if err.code in (401, 403):
                    raise UploadStop(
                        f"STOPP: HTTP {err.code} bei {method} {url} (Scope asset:read/asset:write?)\n"
                        f"Antwort: {detail}",
                        EXIT_AUTH,
                    ) from None
                if (err.code == 429 or err.code >= 500) and attempt < attempts:
                    self._sleep(delay)
                    delay = min(delay * 2, 30.0)
                    continue
                raise UploadStop(f"HTTP {err.code} bei {method} {url}\nAntwort: {detail}", EXIT_INFRA) from None
            except urllib.error.URLError as err:
                if attempt == attempts:
                    raise UploadStop(f"Netzwerkfehler bei {method} {url}: {err.reason}", EXIT_INFRA) from None
                self._sleep(delay)
                delay = min(delay * 2, 30.0)
        raise AssertionError("unreachable")


def multipart(request_json: dict, file_name: str, file_bytes: bytes, boundary: str) -> tuple[bytes, str]:
    parts = [
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n"
        f"Content-Type: application/json\r\n\r\n{json.dumps(request_json)}\r\n".encode(),
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{file_name}\"\r\n"
        f"Content-Type: model/fbx\r\n\r\n".encode() + file_bytes + b"\r\n",
        f"--{boundary}--\r\n".encode(),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def wait_operation(client: Client, operation: dict, poll_seconds: float = 2.0, max_polls: int = 60) -> dict:
    op = operation
    polls = 0
    while not op.get("done"):
        if polls >= max_polls:
            raise UploadStop(f"Operation {op.get('path')} nach {polls} Abfragen nicht fertig.", EXIT_INFRA)
        client._sleep(poll_seconds)
        op_id = op.get("operationId") or str(op.get("path", "")).rsplit("/", 1)[-1]
        op = client.call("GET", f"{API}/operations/{op_id}")
        polls += 1
    if "error" in op:
        raise UploadStop(f"Operation fehlgeschlagen: {client.redact(json.dumps(op['error']))[:500]}", EXIT_INFRA)
    return op.get("response") or {}


def moderation_state(client: Client, asset_id: str, poll_seconds: float = 5.0, max_polls: int = 12) -> str:
    """Liefert Approved, Rejected oder Reviewing (wenn das Warte-Limit erreicht ist)."""
    state = "Reviewing"
    for i in range(max_polls):
        asset = client.call("GET", f"{API}/assets/{asset_id}?readMask=moderationResult")
        state = (asset.get("moderationResult") or {}).get("moderationState") or "Reviewing"
        if state != "Reviewing":
            return state
        if i < max_polls - 1:
            client._sleep(poll_seconds)
    return state


def upload_one(client: Client, path: Path, creator_id: str, boundary: str | None = None) -> dict:
    data = path.read_bytes()
    if len(data) > MAX_BYTES:
        raise UploadStop(f"{path.name} ist groesser als 20 MB.", EXIT_INFRA)
    request_json = {
        "assetType": "Model",
        "displayName": path.stem,
        "description": "Junkyard Magnet art pilot",
        "creationContext": {"creator": {"userId": str(creator_id)}},
    }
    body, content_type = multipart(request_json, path.name, data, boundary or uuid.uuid4().hex)
    operation = client.call("POST", f"{API}/assets", body=body, content_type=content_type)
    response = wait_operation(client, operation)
    asset_id = str(response.get("assetId") or "")
    if not asset_id:
        raise UploadStop(f"{path.name}: keine assetId in der Antwort.", EXIT_INFRA)
    return {"file": path.name, "assetId": asset_id, "status": moderation_state(client, asset_id)}


def write_lock(entries: list[dict], lock_file: Path = LOCK_FILE) -> None:
    existing = {}
    if lock_file.is_file():
        existing = {e["file"]: e for e in json.loads(lock_file.read_text(encoding="utf-8")).get("assets", [])}
    for entry in entries:
        existing[entry["file"]] = {"file": entry["file"], "assetId": entry["assetId"], "status": entry["status"]}
    payload = {"assets": sorted(existing.values(), key=lambda e: e["file"])}
    lock_file.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def run(files: list[Path], client: Client, creator_id: str, lock_file: Path = LOCK_FILE) -> int:
    if len(files) > MAX_UPLOADS:
        raise UploadStop(f"{len(files)} Dateien > Pilot-Grenze {MAX_UPLOADS}.", EXIT_INFRA)
    done: list[dict] = []
    try:
        for path in files:
            entry = upload_one(client, path, creator_id)
            done.append(entry)
            print(f"{entry['file']}: asset {entry['assetId']} {entry['status']}")
            if entry["status"] == "Rejected":
                raise UploadStop(f"Moderation hat {entry['file']} abgelehnt - weitere Uploads gestoppt.",
                                 EXIT_REJECTED)
    finally:
        if done:
            write_lock(done, lock_file)
    return 0


def main(argv: list[str]) -> int:
    files = [Path(a).resolve() for a in argv] or [EXPORT_DIR / name for name in PILOT_FILES]
    missing = [p.name for p in files if not p.is_file()]
    try:
        if missing:
            raise UploadStop(f"Dateien fehlen: {', '.join(missing)}", EXIT_INFRA)
        key, creator = load_config()
        client = Client(key)
        try:
            return run(files, client, creator)
        except UploadStop as stop:
            stop.args = (client.redact(str(stop)),)
            raise
    except UploadStop as stop:
        print(str(stop), file=sys.stderr)
        return stop.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
