"""Laedt build/spike.rbxl als neue Version in den Ziel-Place hoch und gibt NUR die Versionsnummer aus.

Doku: https://create.roblox.com/docs/cloud/guides/usage-place-publishing
"""

import argparse
import sys

from _common import EXIT_INFRA, PLACE_FILE, fail, request, target_config


def publish(target: str) -> int:
    api_key, universe_id, place_id = target_config(target)
    if not PLACE_FILE.is_file():
        fail(f"{PLACE_FILE} fehlt - zuerst tools/spike/build.py ausfuehren.", EXIT_INFRA)
    url = f"https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions?versionType=Published"
    result = request(
        "POST",
        url,
        api_key,
        body=PLACE_FILE.read_bytes(),
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
    args = parser.parse_args()
    print(publish(args.target))
    return 0


if __name__ == "__main__":
    sys.exit(main())
