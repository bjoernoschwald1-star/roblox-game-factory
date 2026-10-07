"""Sucht die Werte von ROBLOX_CI_API_KEY und ROBLOX_STAGING_API_KEY (Pflicht) sowie - falls gesetzt - der
optionalen Schluessel aus OPTIONAL_SECRET_VARS (z. B. ROBLOX_ASSETS_API_KEY) in allen Repo-Dateien (inkl. build/,
build/logs/ und games/*/art/assets.lock.json) sowie in optional uebergebenen Dateien/Ordnern.

Ausgenommen sind nur .env (Quelle der Schluessel) und .git/. Fund = Exit 1; fehlt ein Pflichtschluessel = Exit 2.
Fehlende optionale Schluessel sind kein Fehler (z. B. in der CI). Optionale Werte unter MIN_OPTIONAL_LENGTH (16)
Zeichen werden nicht als Suchwert benutzt: Ein leerer oder sehr kurzer Platzhalter in .env wuerde sonst in
beliebigen Dateien Scheinfunde erzeugen; echte API-Schluessel sind deutlich laenger.
Es wird nie ein Schluessel und nie der Name eines gesetzten Schluessels zusammen mit Inhalten ausgegeben, nur
Dateipfade und die Zaehlzeile "check_secrets: N Dateien geprueft, M Funde (optional: x von y)".
"""

import sys
from pathlib import Path

from _common import OPTIONAL_SECRET_VARS, REPO_ROOT, SECRET_VARS, optional_secret_values, secret_values

SKIP = (REPO_ROOT / ".env", REPO_ROOT / ".git")
MIN_OPTIONAL_LENGTH = 16


def iter_files(root: Path, skip: tuple[Path, ...]):
    if root.is_file():
        yield root
        return
    for path in root.rglob("*"):
        if path.is_file() and not any(path == s or s in path.parents for s in skip):
            yield path


def usable_optional(values: list[str]) -> list[str]:
    """Optionale Werte, die als Suchwert taugen (mindestens MIN_OPTIONAL_LENGTH Zeichen)."""
    return [v for v in values if v and len(v) >= MIN_OPTIONAL_LENGTH]


def scan(roots: list[Path], needles: list[bytes], skip: tuple[Path, ...] | None = None) -> tuple[list[Path], int]:
    """Durchsucht alle Dateien unter roots nach needles (ohne skip, Standard SKIP); liefert (Fundpfade, Anzahl)."""
    excluded = SKIP if skip is None else skip
    scanned, hits = 0, []
    for root in roots:
        for path in iter_files(root, excluded):
            scanned += 1
            if any(n in path.read_bytes() for n in needles):
                hits.append(path)
    return hits, scanned


def main() -> int:
    required = secret_values()
    if len(required) != len(SECRET_VARS):
        print(f"Nicht alle Schluesselvariablen gesetzt ({', '.join(SECRET_VARS)}).", file=sys.stderr)
        return 2
    optional = usable_optional(optional_secret_values())
    needles = [v.encode() for v in required + optional]
    roots = [REPO_ROOT] + [Path(p).resolve() for p in sys.argv[1:]]
    hits, scanned = scan(roots, needles)
    for path in hits:
        print(f"FUND: Schluesselwert in {path}")
    print(
        f"check_secrets: {scanned} Dateien geprueft, {len(hits)} Funde "
        f"(optional: {len(optional)} von {len(OPTIONAL_SECRET_VARS)})"
    )
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
