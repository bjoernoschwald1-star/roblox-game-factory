"""Grenzcheck der Core Engine: core/src darf keine Theme-Begriffe und keine Asset-IDs enthalten.

Durchsucht alle Dateien unter core/src (oder die uebergebenen Dateien/Ordner) nach den Begriffen
junkyard, magnet, scrap, schrott, treasure, deepsea und deep_sea - ohne Ruecksicht auf
Gross-/Kleinschreibung, aber nur als ganzes Wort. Als Wortgrenze gilt jedes Zeichen ausser Buchstabe
oder Ziffer (also auch der Unterstrich) sowie ein Wechsel von Klein- zu Grossbuchstabe (camelCase):
"junkyardZone", "Magnet_Pull" und "DeepSea" werden gefunden, "search", "season" und "deepEqual" nicht.
"rbxassetid" wird ueberall gefunden, auch als Teil eines Strings wie "rbxassetid://123".
Fund = Exit 1, fehlender Pfad = Exit 2.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ROOT = REPO_ROOT / "core" / "src"
WORDS = ("junkyard", "magnet", "scrap", "schrott", "treasure", "deepsea", "deep_sea")

# Die Grenzen pruefen die Gross-/Kleinschreibung, daher gilt (?i:...) nur fuer den Begriff selbst.
_START = r"(?:(?<![A-Za-z0-9])|(?<=[a-z])(?=[A-Z]))"
_END = r"(?:(?![A-Za-z0-9])|(?<=[a-z])(?=[A-Z]))"
PATTERNS = [(word, re.compile(_START + f"(?i:{re.escape(word)})" + _END)) for word in WORDS]
PATTERNS.append(("rbxassetid", re.compile("(?i:rbxassetid)")))


def iter_files(root: Path):
    if root.is_file():
        yield root
        return
    for path in sorted(root.rglob("*")):
        if path.is_file():
            yield path


def display(path: Path) -> Path:
    return path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path


def main() -> int:
    roots = [Path(p).resolve() for p in sys.argv[1:]] or [DEFAULT_ROOT]
    missing = [root for root in roots if not root.exists()]
    if missing:
        print(f"core_boundary: Pfad fehlt: {', '.join(str(m) for m in missing)}", file=sys.stderr)
        return 2
    scanned, hits = 0, 0
    for root in roots:
        for path in iter_files(root):
            scanned += 1
            text = path.read_text(encoding="utf-8", errors="replace")
            for lineno, line in enumerate(text.splitlines(), start=1):
                for word, pattern in PATTERNS:
                    for match in pattern.finditer(line):
                        hits += 1
                        print(f"FUND: {display(path)}:{lineno}: {word} ({match.group(0)!r})")
    print(f"core_boundary: {scanned} Dateien geprueft, {hits} Funde")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
