#!/usr/bin/env python3
"""Exercise build orchestration in a disposable tree, without Docker or a phone."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "0100-arm64-dts-exynos990-r8s-6gb-memory-map.patch"


class BuildRecipes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ("packaging/build-env/build-m1-kernel.sh",
                     "packaging/build-env/build-arch-rootfs.sh"):
            self.put(name, (ROOT / name).read_text())
        self.put("sources/port/kernel/patches/0001-port.patch", "fixture")
        self.put("sources/port/kernel/config/r8s.config", "fixture")
        self.put("sources/linux/arch/arm64/boot/dts/exynos/exynos990-r8s.dts", "fixture")
        self.put("sources/linux/scripts/config", '#!/bin/sh\necho "$*" >> "$TRACE"\n', True)
        for name in ("amss.bin", "m3.bin", "board-2.bin"):
            self.put(f"blobs/firmware/ath11k/QCA6390/hw2.0/{name}", "fixture")
        self.series = [BASELINE, "0102-gpu.patch", "0103-idle.patch",
                       "0104-i2c.patch", "0105-suspend.patch"]
        for name in self.series + ["0101-haptic.patch"]:
            self.put(f"packaging/kernel-patches/{name}", "fixture")
        self.put("packaging/kernel-patches/series", "# ordered\n\n" + "\n".join(self.series) + "\n")
        self.put("bin/docker", '''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
for i, arg in enumerate(args):
    if arg == "-e":
        key, value = args[i + 1].split("=", 1)
        os.environ[key] = value
script = args[args.index("-c") + 1].replace("/tmp", os.environ["FIXTURE"] + "/tmp")
script = script.replace("/work", os.environ["FIXTURE"])
os.execvp("bash", ["bash", "-euo", "pipefail", "-c", script])
''', True)
        self.put("bin/rsync", '''#!/usr/bin/env python3
import shutil, sys
shutil.copytree(sys.argv[-2], sys.argv[-1], dirs_exist_ok=True)
''', True)
        self.put("bin/git", '#!/bin/sh\n[ "$1" != apply ] || echo "apply $(basename "$2")" >> "$TRACE"\n', True)
        self.put("bin/make", '''#!/bin/sh
case "$*" in
  *kernelrelease*) echo fixture-r8s ;;
  *modules_install*)
    mkdir -p "$FIXTURE/out/staging/modstage/lib/modules/fixture-r8s"
    touch "$FIXTURE/out/staging/modstage/lib/modules/fixture-r8s/modules.dep" ;;
  *)
    mkdir -p arch/arm64/boot/dts/exynos
    touch arch/arm64/boot/Image arch/arm64/boot/dts/exynos/exynos990-r8s.dtb ;;
esac
''', True)
        self.env = dict(os.environ, PATH=f"{self.root}/bin:{os.environ['PATH']}",
                        FIXTURE=str(self.root), TRACE=str(self.root / "trace"))
        self.env.pop("R8S_KERNEL_PATCHSET", None)

    def put(self, name, data, executable=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        if executable:
            path.chmod(0o755)

    def run_recipe(self, name="build-m1-kernel.sh", mode="kernel", patchset=None):
        env = self.env.copy()
        if patchset is not None:
            env["R8S_KERNEL_PATCHSET"] = patchset
        return subprocess.run(["bash", str(self.root / "packaging/build-env" / name), mode],
                              env=env, text=True, capture_output=True)

    def test_default_excludes_experimental_patches(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "trace").read_text().splitlines(),
                         ["apply 0001-port.patch", f"apply {BASELINE}"])

    def test_series_order_and_thermal_config(self):
        result = self.run_recipe(patchset="series")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "trace").read_text().splitlines(),
                         ["apply 0001-port.patch"] + [f"apply {p}" for p in self.series]
                         + ["-e DEVFREQ_THERMAL"])

    def test_dtbs_rejected_before_changing_outputs(self):
        self.put("out/boot/kernel-release.txt", "existing")
        result = self.run_recipe(mode="dtbs")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("full kernel build", result.stdout + result.stderr)
        self.assertEqual((self.root / "out/boot/kernel-release.txt").read_text(), "existing")
        self.assertFalse((self.root / "trace").exists())

    def test_unknown_patchset_rejected(self):
        self.assertNotEqual(self.run_recipe(patchset="typo").returncode, 0)
        self.assertFalse((self.root / "trace").exists())

    def test_missing_series_patch_rejected(self):
        (self.root / "packaging/kernel-patches/0102-gpu.patch").unlink()
        self.assertNotEqual(self.run_recipe(patchset="series").returncode, 0)

    def test_series_path_escape_rejected(self):
        self.put("packaging/kernel-patches/series", "../escape.patch\n")
        self.put("packaging/escape.patch", "fixture")
        self.assertNotEqual(self.run_recipe(patchset="series").returncode, 0)

    def test_empty_series_rejected(self):
        self.put("packaging/kernel-patches/series", "# no patches\n\n")
        self.assertNotEqual(self.run_recipe(patchset="series").returncode, 0)

    def test_bluetooth_preflight_checks_both_blobs(self):
        for name in (ROOT / "packaging/rootfs-glue").iterdir():
            if name.is_file():
                self.put(f"packaging/rootfs-glue/{name.name}", "fixture")
        entries = []
        for name in ("htbtfw20.tlv", "htnv20.bin"):
            path = f"blobs/r8s-device/vendor/root/firmware/{name}"
            self.put(path, name)
            entries.append(f"{hashlib.sha256(name.encode()).hexdigest()}  {path}\n")
        self.put("manifests/bluetooth-firmware.sha256", "".join(entries))
        result = self.run_recipe("build-arch-rootfs.sh", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in ("htbtfw20.tlv", "htnv20.bin"):
            with self.subTest(blob=name):
                path = f"blobs/r8s-device/vendor/root/firmware/{name}"
                self.put(path, "corrupt")
                self.assertNotEqual(self.run_recipe("build-arch-rootfs.sh", "--dry-run").returncode, 0)
                (self.root / path).unlink()
                self.assertNotEqual(self.run_recipe("build-arch-rootfs.sh", "--dry-run").returncode, 0)
                self.put(path, name)


if __name__ == "__main__":
    unittest.main()
