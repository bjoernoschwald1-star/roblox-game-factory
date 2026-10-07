"""Sucht die Werte von ROBLOX_CI_API_KEY und ROBLOX_STAGING_API_KEY in allen Repo-Dateien
(inkl. build/ und build/logs/) sowie in optional uebergebenen Dateien/Ordnern.

Ausgenommen sind nur .env (Quelle der Schluessel) und .git/. Fund = Exit 1.
Es wird nie ein Schluessel ausgegeben, nur Dateipfade.
"""

import sys
from pathlib import Path

from _common import REPO_ROOT, SECRET_VARS, secret_values

SKIP = (REPO_ROOT / ".env", REPO_ROOT / ".git")


def iter_files(root: Path):
    if root.is_file():
        yield root
        return
    for path in root.rglob("*"):
        if path.is_file() and not any(path == s or s in path.parents for s in SKIP):
            yield path


def main() -> int:
    needles = [v.encode() for v in secret_values()]
    if len(needles) != len(SECRET_VARS):
        print(f"Nicht alle Schluesselvariablen gesetzt ({', '.join(SECRET_VARS)}).", file=sys.stderr)
        return 2
    roots = [REPO_ROOT] + [Path(p).resolve() for p in sys.argv[1:]]
    scanned, hits = 0, []
    for root in roots:
        for path in iter_files(root):
            scanned += 1
            if any(n in path.read_bytes() for n in needles):
                hits.append(path)
    for path in hits:
        print(f"FUND: Schluesselwert in {path}")
    print(f"check_secrets: {scanned} Dateien geprueft, {len(hits)} Funde")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
