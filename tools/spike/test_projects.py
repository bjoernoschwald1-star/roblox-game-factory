"""Tooling-Tests 114 und 131: Inhalt der beiden Rojo-Projekte ueber die Sourcemap, Grenzen der Client-Config.

- testbed.project.json (Staging): kein FactoryCoreTests, kein Spike, kein Test-Hilfsordner; mit Server- und
  Client-Skript des Testbeds. ServerConfig nur in ServerScriptService, ClientConfig in ReplicatedStorage.
- default.project.json (CI-Place): Tests und Spike, aber kein Testbed-Server- oder Client-Skript; World und
  ServerConfig nur als ModuleScripts im Testeintrag ServerScriptService.TestbedServerUnderTest.
- ClientConfig.luau eines Games enthaelt keine Schluessel products, passes, remotes, sim, productId, passId, price,
  spawnWeight (gleiche Liste wie Luau-Test 116).
Die Sourcemap-Tests brauchen rojo im PATH (in der CI aus Rokit); ohne rojo werden sie uebersprungen.
"""

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SERVER_ONLY_KEYS = ("products", "passes", "remotes", "sim", "productId", "passId", "price", "spawnWeight")


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
        under_test = "factory-spike/ServerScriptService/TestbedServerUnderTest"
        self.assertIn((f"{under_test}/World", "ModuleScript"), tree)
        self.assertIn((f"{under_test}/ServerConfig", "ModuleScript"), tree)
        self.assertNotIn("factory-spike/ServerScriptService/TestbedWorld", paths)

    def test_131_server_config_only_on_the_server(self):
        tree = instances(sourcemap("testbed.project.json"))
        server_configs = [path for path, _ in tree if path.endswith("/ServerConfig")]
        self.assertEqual(server_configs, ["factory-testbed/ServerScriptService/TestbedServer/ServerConfig"])
        self.assertIn(("factory-testbed/ReplicatedStorage/TestbedShared/ClientConfig", "ModuleScript"), tree)
        replicated = [path for path, _ in tree if path.startswith("factory-testbed/ReplicatedStorage/")]
        self.assertFalse([path for path in replicated if path.endswith("/Config") or "ServerConfig" in path])


class ClientConfigTest(unittest.TestCase):
    def test_131_client_configs_have_no_server_only_keys(self):
        files = sorted(REPO_ROOT.glob("games/*/shared/ClientConfig.luau"))
        self.assertTrue(files, "keine ClientConfig.luau gefunden")
        pattern = re.compile(r"(?<![\w.])(" + "|".join(SERVER_ONLY_KEYS) + r")\s*=")
        for path in files:
            code = "\n".join(line.split("--", 1)[0] for line in path.read_text(encoding="utf-8").splitlines())
            self.assertEqual(pattern.findall(code), [], str(path.relative_to(REPO_ROOT)))


if __name__ == "__main__":
    unittest.main()
