"""Baut build/spike.rbxl mit Rojo (rojo build -o build/spike.rbxl)."""

import subprocess
import sys

from _common import BUILD_DIR, REPO_ROOT


def main() -> int:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    return subprocess.call(["rojo", "build", "-o", "build/spike.rbxl"], cwd=REPO_ROOT)


if __name__ == "__main__":
    sys.exit(main())
