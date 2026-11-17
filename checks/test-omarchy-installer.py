#!/usr/bin/env python3
"""Run the installer against a disposable filesystem; never configure the host."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTarget(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        script = (ROOT / "packaging/omarchy/install-omarchy-r8s.sh").read_text()
        for prefix in ("/etc/", "/sys/", "/opt/", "/usr/", "/run/"):
            script = script.replace(prefix, str(self.root) + prefix)
        self.put("installer.sh", script)
        self.put("etc/os-release", "ID=archarm\n")
        self.put("etc/pacman.conf", "[options]\n[core]\n")
        self.put("sys/firmware/devicetree/base/compatible", "samsung,r8s\0samsung,exynos990\0")
        self.put("opt/mesa-g77/present", "fixture")
        self.put("bin/uname", '#!/bin/sh\necho "${MOCK_ARCH:-aarch64}"\n')
        self.put("bin/id", '#!/bin/sh\n[ "$1" != -u ] || echo 0\n')
        self.put("bin/systemctl", "#!/bin/sh\nexit 1\n")
        self.put("bin/df", '#!/bin/sh\nprintf "Filesystem Size Used Avail Use%% Mounted\\n/dev/sda32 9000 1000 8000 10%% /\\n"\n')
        # Stop on the first attempted network operation; earlier /etc changes are sandboxed.
        self.put("bin/curl", "#!/bin/sh\nexit 77\n")
        self.env = dict(os.environ, PATH=f"{self.root}/bin:{os.environ['PATH']}")
        self.env.pop("R8S_MESA_G77_PKG", None)

    def put(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        if name.startswith("bin/"):
            path.chmod(0o755)

    def run_installer(self, *args):
        return subprocess.run(["bash", str(self.root / "installer.sh"), *args],
                              env=self.env, text=True, capture_output=True)

    def assert_rejected_before_configuration(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual((self.root / "etc/pacman.conf").read_text(), "[options]\n[core]\n")

    def test_x86_host_rejected(self):
        self.env["MOCK_ARCH"] = "x86_64"
        self.assert_rejected_before_configuration()

    def test_other_arm_device_rejected(self):
        self.put("sys/firmware/devicetree/base/compatible", "samsung,r8q\0")
        self.assert_rejected_before_configuration()

    def test_missing_device_tree_rejected(self):
        (self.root / "sys/firmware/devicetree/base/compatible").unlink()
        self.assert_rejected_before_configuration()

    def test_other_distribution_rejected(self):
        self.put("etc/os-release", "ID=debian\n")
        self.assert_rejected_before_configuration()

    def test_r8s_arch_reaches_installation(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 77, result.stdout + result.stderr)
        self.assertIn("[omarchy]", (self.root / "etc/pacman.conf").read_text())

    def test_dry_run_on_host_still_has_no_side_effects(self):
        self.env["MOCK_ARCH"] = "x86_64"
        self.assertEqual(self.run_installer("--dry-run").returncode, 0)
        self.assertEqual((self.root / "etc/pacman.conf").read_text(), "[options]\n[core]\n")


if __name__ == "__main__":
    unittest.main()
