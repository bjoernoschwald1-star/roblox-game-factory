"""Baut einen Place mit Rojo.

Standard: default.project.json -> build/spike.rbxl (Test-Build fuer den CI-Place).
Mit --project testbed.project.json -> build/testbed.rbxl (spielbares Testbed fuer Staging).
Allgemein: <name>.project.json -> build/<name>.rbxl; default.project.json bleibt build/spike.rbxl.
"""

import argparse
import subprocess
import sys
from pathlib import Path

from _common import BUILD_DIR, REPO_ROOT

DEFAULT_PROJECT = "default.project.json"


def output_for(project: str) -> Path:
    name = Path(project).name
    if name == DEFAULT_PROJECT:
        return BUILD_DIR / "spike.rbxl"
    return BUILD_DIR / (name.removesuffix(".project.json") + ".rbxl")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=DEFAULT_PROJECT, help="Rojo-Projektdatei im Repo-Wurzelordner")
    args = parser.parse_args()
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    output = output_for(args.project)
    return subprocess.call(["rojo", "build", args.project, "-o", str(output.relative_to(REPO_ROOT))], cwd=REPO_ROOT)


if __name__ == "__main__":
    sys.exit(main())
