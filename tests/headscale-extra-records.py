"""Run with python3 tests/headscale-extra-records.py (requires nix, bash and jq)."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RECORDS = "/var/lib/headscale/extra-records.json"


class ExtraRecordsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads(subprocess.check_output([
            "nix", "eval", "--json",
            ".#nixosConfigurations.alcyone.config.systemd",
            "--apply", """s: {
              script = s.services.headscale-extra-records.script;
              preStart = s.services.headscale.preStart;
              service = s.services.headscale-extra-records.serviceConfig;
              startLimit = s.services.headscale-extra-records.startLimitIntervalSec;
              timer = s.timers.headscale-extra-records.timerConfig;
            }""",
        ], cwd=ROOT, text=True))
        cls.mapping = json.loads(re.search(
            r"--argjson mapping '([^']+)'", cls.config["script"]
        )[1])

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.records = self.directory / "records.json"
        self.fixture = self.directory / "nodes.json"
        mock = self.directory / "headscale"
        mock.write_text(
            '#!/bin/sh\n'
            'if [ "$FAIL_API" = 1 ]; then\n'
            '  echo "API unavailable" >&2; exit 1\n'
            'fi\n'
            'cat "$NODES"\n'
        )
        mock.chmod(0o755)
        self.nodes = [
            {"given_name": name,
             "ip_addresses": [f"100.77.0.{i}", f"fd7a:115c:a1e0:77::{i}"],
             "online": False}
            for i, name in enumerate(sorted(set(self.mapping.values())), 1)
        ]
        self.env = dict(os.environ, PATH=f"{self.directory}:{os.environ['PATH']}",
                        NODES=str(self.fixture), FAIL_API="0")

    def run_script(self, script):
        return subprocess.run(
            ["bash", "-c", script.replace(RECORDS, str(self.records))],
            env=self.env, capture_output=True, text=True, timeout=10,
        )

    def generate(self, nodes=None):
        self.fixture.write_text(json.dumps(self.nodes if nodes is None else nodes))
        return self.run_script(self.config["script"])

    def test_bootstrap_preserves_existing_records(self):
        self.assertEqual(self.run_script(self.config["preStart"]).returncode, 0)
        self.assertEqual(json.loads(self.records.read_text()), [])
        self.records.write_text('[{"name":"known-good"}]\n')
        before = self.records.read_bytes()
        self.assertEqual(self.run_script(self.config["preStart"]).returncode, 0)
        self.assertEqual(self.records.read_bytes(), before)

    def test_offline_nodes_and_unchanged_snapshot(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        records = json.loads(self.records.read_text())
        self.assertEqual(len(records), 2 * len(self.mapping))
        self.assertEqual({r["name"] for r in records}, set(self.mapping))
        self.assertTrue(all(r["value"] for r in records))
        inode = self.records.stat().st_ino
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(self.records.stat().st_ino, inode)

    def test_bad_snapshots_preserve_good_file_and_recover(self):
        self.assertEqual(self.generate().returncode, 0)
        before = self.records.read_bytes()
        incomplete = [dict(node) for node in self.nodes]
        incomplete[0] = dict(incomplete[0], ip_addresses=["100.77.0.1"])
        cases = [[], {}, None, self.nodes[1:], incomplete]
        for nodes in cases:
            with self.subTest(nodes=nodes):
                # None is deliberately JSON null, not generate()'s default.
                self.fixture.write_text(json.dumps(nodes))
                result = self.run_script(self.config["script"])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.records.read_bytes(), before)
                self.assertFalse(list(self.directory.glob("records.json.*")))
        self.fixture.write_text("not json")
        self.assertNotEqual(self.run_script(self.config["script"]).returncode, 0)
        self.assertEqual(self.records.read_bytes(), before)
        self.env["FAIL_API"] = "1"
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("API unavailable", result.stderr)
        self.assertEqual(self.records.read_bytes(), before)
        self.env["FAIL_API"] = "0"
        self.nodes[0]["ip_addresses"] = ["100.77.0.99", "fd7a:115c:a1e0:77::99"]
        self.assertEqual(self.generate().returncode, 0)
        self.assertNotEqual(self.records.read_bytes(), before)

    def test_retry_and_periodic_schedule(self):
        self.assertEqual(self.config["startLimit"], 0)
        self.assertEqual(self.config["service"]["Restart"], "on-failure")
        self.assertEqual(self.config["service"]["RestartSec"], "15s")
        self.assertEqual(self.config["service"]["TimeoutStartSec"], "30s")
        self.assertEqual(self.config["timer"]["OnActiveSec"], "1s")
        self.assertEqual(self.config["timer"]["OnCalendar"], "hourly")
        self.assertTrue(self.config["timer"]["Persistent"])


if __name__ == "__main__":
    unittest.main()
