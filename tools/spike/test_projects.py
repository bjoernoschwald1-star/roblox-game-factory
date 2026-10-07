"""Tooling-Test 114: Inhalt der beiden Rojo-Projekte ueber die Sourcemap.

- testbed.project.json (Staging): kein FactoryCoreTests, kein Spike, kein Test-Hilfsordner; mit Server- und
  Client-Skript des Testbeds.
- default.project.json (CI-Place): Tests und Spike, aber kein Testbed-Server- oder Client-Skript.
Braucht rojo im PATH (in der CI aus Rokit); ohne rojo wird der Test uebersprungen.
"""

import json
import shutil
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def sourcemap(project: str) -> dict:
    output = subprocess.run(
        ["rojo", "sourcemap", project], cwd=REPO_ROOT, capture_output=True, text=True, check=True
    ).stdout
    return json.loads(output)


def instances(node: dict, path: str = "") -> list[tuple[str, str]]:
    here = f"{path}/{node['name']}" if path else node["name"]
    found = [(here, node["className"])]
    for child in node.get("children", []):
        found.extend(instances(child, here))
    return found


@unittest.skipUnless(shutil.which("rojo"), "rojo nicht im PATH")
class ProjectsTest(unittest.TestCase):
    def test_testbed_build_has_no_tests_and_both_scripts(self):
        tree = instances(sourcemap("testbed.project.json"))
        paths = [path for path, _ in tree]
        self.assertFalse([p for p in paths if "FactoryCoreTests" in p or "/Spike" in p])
        self.assertFalse([p for p in paths if p.startswith("factory-testbed/ServerScriptService/FactoryCore/testing")])
        self.assertIn(("factory-testbed/ServerScriptService/TestbedServer/Main", "Script"), tree)
        self.assertIn(
            ("factory-testbed/StarterPlayer/StarterPlayerScripts/TestbedClient/Main", "LocalScript"), tree
        )
        for folder in ("FactoryClient", "FactoryKit", "TestbedShared"):
            self.assertIn((f"factory-testbed/ReplicatedStorage/{folder}", "Folder"), tree)

    def test_ci_build_has_no_testbed_scripts(self):
        tree = instances(sourcemap("default.project.json"))
        scripts = [(path, cls) for path, cls in tree if cls in ("Script", "LocalScript")]
        self.assertEqual(scripts, [])
        paths = [path for path, _ in tree]
        self.assertIn("factory-spike/ServerScriptService/FactoryCoreTests", paths)
        self.assertNotIn("factory-spike/StarterPlayer", paths)
        for folder in ("FactoryClient", "FactoryKit", "TestbedShared"):
            self.assertIn(f"factory-spike/ReplicatedStorage/{folder}", paths)


if __name__ == "__main__":
    unittest.main()
