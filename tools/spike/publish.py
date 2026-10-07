"""Laedt einen gebauten Place (Standard build/spike.rbxl) als neue Version in den Ziel-Place hoch und gibt NUR die
Versionsnummer aus. Mit --file laesst sich ein anderer Build waehlen, z. B. build/testbed.rbxl fuer Staging.

Doku: https://create.roblox.com/docs/cloud/guides/usage-place-publishing
"""

import argparse
import sys
from pathlib import Path

from _common import EXIT_INFRA, PLACE_FILE, REPO_ROOT, fail, request, target_config


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("ci", "staging"), required=True)
    parser.add_argument("--file", help="Place-Datei relativ zum Repo-Wurzelordner (Standard build/spike.rbxl)")
    args = parser.parse_args()
    place_file = (REPO_ROOT / args.file) if args.file else PLACE_FILE
    print(publish(args.target, place_file))
    return 0


if __name__ == "__main__":
    sys.exit(main())
