#!/usr/bin/env python3
"""Exercise build orchestration in a disposable tree, without Docker or a phone."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "0100-arm64-dts-exynos990-r8s-6gb-memory-map.patch"
CLOCK_FIXES = "0107-r8s-ufs-sync-and-unavailable-clocks.patch"


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
        for name in ("amss.bin", "m3.bin", "board-2.bin", "board-2.r8s.bin"):
            self.put(f"blobs/firmware/ath11k/QCA6390/hw2.0/{name}", "fixture")
        self.series = [BASELINE, "0102-gpu.patch", "0103-idle.patch",
                       "0104-i2c.patch", "0105-suspend.patch", CLOCK_FIXES]
        for name in self.series + ["0101-haptic.patch"]:
            self.put(f"packaging/kernel-patches/{name}", "fixture")
        self.put("packaging/kernel-patches/series", "# ordered\n\n" + "\n".join(self.series) + "\n")
        self.put("bin/docker", '''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
for i, arg in enumerate(args):
    if arg == "-e":
        key, value = args[i + 1].split("=", 1)
        os.environ[key] = value.replace("/work", os.environ["FIXTURE"])
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
        args = ["bash", str(self.root / "packaging/build-env" / name)]
        if mode:
            args.append(mode)
        return subprocess.run(args, env=env, text=True, capture_output=True,
                              stdin=subprocess.DEVNULL)

    def test_default_excludes_experimental_patches(self):
        result = self.run_recipe()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "trace").read_text().splitlines(),
                         ["apply 0001-port.patch", f"apply {BASELINE}", f"apply {CLOCK_FIXES}", "--set-str EXTRA_FIRMWARE "])

    def test_series_order_and_kernel_config(self):
        result = self.run_recipe(patchset="series")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.root / "trace").read_text().splitlines(),
                         ["apply 0001-port.patch"] + [f"apply {p}" for p in self.series]
                         + ["--set-str EXTRA_FIRMWARE ", "-e DEVFREQ_THERMAL",
                            "-e MEDIA_SUPPORT -e MEDIA_PLATFORM_SUPPORT -e MEDIA_PLATFORM_DRIVERS "
                            "-e VIDEO_DEV -e MEDIA_CONTROLLER",
                            "-e REGULATOR_S2MPS22_ACPM -e PHY_EXYNOS990_MIPI_CSI "
                            "-e VIDEO_EXYNOS990_CSIS -e VIDEO_S5K2LD"])

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

    def prepare_package_fixture(self):
        self.put("bin/rsync", '''#!/usr/bin/env python3
import shutil, sys
shutil.copytree(sys.argv[-2], sys.argv[-1], dirs_exist_ok=True)
''', True)
        self.assertEqual(self.run_recipe().returncode, 0)
        self.put("blobs/slk-stock.dtb", "stock")
        self.put("out/boot/initramfs-slim.cpio.gz", "slim")
        slim = self.root / "out/boot/initramfs-slim.cpio.gz"
        self.put("out/boot/initramfs-slim.sha256",
                 f"{hashlib.sha256(slim.read_bytes()).hexdigest()}  {slim}\n")
        self.put("out/boot/initramfs-slim.kernel.sha256",
                 (self.root / "out/boot/kernel.sha256").read_text())
        self.put("sources/uniLoader/blob/fixture", "loader")
        # A sentinel stops before compilation; reaching it proves preflight passed.
        self.put("bin/rsync", '#!/bin/sh\nexit 77\n', True)

    def test_matching_package_inputs_reach_loader_build(self):
        self.prepare_package_fixture()
        self.assertEqual(self.run_recipe(mode="package").returncode, 77)

    def test_corrupt_kernel_inputs_rejected_before_loader_build(self):
        for name in ("out/boot/Image", "out/boot/exynos990-r8s.dtb",
                     "out/modules-fixture-r8s.tar.gz"):
            with self.subTest(input=name):
                self.prepare_package_fixture()
                self.put(name, "changed")
                result = self.run_recipe(mode="package")
                self.assertNotIn(result.returncode, (0, 77), result.stdout + result.stderr)

    def test_stale_slim_with_same_release_rejected(self):
        self.prepare_package_fixture()
        self.put("out/boot/initramfs-slim.kernel.sha256", "previous-build-same-release")
        result = self.run_recipe(mode="package")
        self.assertNotIn(result.returncode, (0, 77), result.stdout + result.stderr)

    def test_missing_slim_provenance_rejected(self):
        self.prepare_package_fixture()
        (self.root / "out/boot/initramfs-slim.kernel.sha256").unlink()
        self.assertNotIn(self.run_recipe(mode="package").returncode, (0, 77))

    def test_corrupt_slim_rejected(self):
        self.prepare_package_fixture()
        self.put("out/boot/initramfs-slim.cpio.gz", "corrupt")
        self.assertNotIn(self.run_recipe(mode="package").returncode, (0, 77))

    def test_missing_stock_dtb_rejected(self):
        self.prepare_package_fixture()
        (self.root / "blobs/slk-stock.dtb").unlink()
        self.assertNotIn(self.run_recipe(mode="package").returncode, (0, 77))

    def prepare_arch_fixture(self):
        for name in (ROOT / "packaging/rootfs-glue").iterdir():
            if name.is_file():
                self.put(f"packaging/rootfs-glue/{name.name}", "fixture")
        entries = []
        for name in ("htbtfw20.tlv", "htnv20.bin"):
            path = f"blobs/r8s-device/vendor/root/firmware/{name}"
            self.put(path, name)
            entries.append(f"{hashlib.sha256(name.encode()).hexdigest()}  {path}\n")
        self.put("manifests/bluetooth-firmware.sha256", "".join(entries))

    def test_bluetooth_preflight_checks_both_blobs(self):
        self.prepare_arch_fixture()
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

    def prepare_arch_build(self):
        self.prepare_arch_fixture()
        self.put("key.pub", "test-public-key")
        self.env.update(R8S_USERPW="test-only", R8S_SSH_PUBKEY_FILE=str(self.root / "key.pub"))
        self.put("out/boot/kernel-release.txt", "kernelrelease=fixture-r8s\n")
        self.put("module/modules.dep", "")
        with tarfile.open(self.root / "out/modules-fixture-r8s.tar.gz", "w:gz") as archive:
            archive.add(self.root / "module/modules.dep", arcname="modules.dep")
        for name in ("ufs-root.img", "ufs-root.sha256", "arch-base-packages.txt"):
            self.put(f"out/rootfs/{name}", "previous-good-artifact")
        self.put("blobs/firmware/ath11k/QCA6390/hw2.0/Notice.txt", "fixture")
        for name in ("r8s-charge-limit.sh", "r8s-charge-limit.rules", "r8s-netwatch.sh", "r8s-netwatch.service"):
            self.put(f"sources/port/device/{name}", "fixture")
        for command in ("curl", "bsdtar", "pacman-key", "mount", "chroot", "chown"):
            self.put(f"bin/{command}", "#!/bin/sh\nexit 0\n", True)
        self.put("bin/sha256sum", '''#!/bin/sh
if [ "$*" = "-c -" ]; then cat >/dev/null; exit 0; fi
exec /usr/bin/sha256sum "$@"
''', True)
        self.put("bin/pacman", '''#!/bin/sh
case "$*" in
  *" -Q") echo "base 1" ;;
  *)
    MNT="$FIXTURE/tmp/archmnt"
    touch "$MNT/dev/host-sentinel"
    [ "${FAIL_AT:-}" != install ] || exit 42
    mkdir -p "$MNT/etc/ssh/sshd_config.d" "$MNT/etc/systemd/system" "$MNT/etc/pacman.d"
    printf "[options]\\n#IgnorePkg =\\n[core]\\n" > "$MNT/etc/pacman.conf" ;;
esac
''', True)
        self.put("bin/umount", '#!/bin/sh\n[ "${FAIL_AT:-}" != install ]\n', True)
        self.put("bin/mkfs.ext4", '''#!/bin/bash
for name in htbtfw20.tlv htnv20.bin; do
  cmp "$FIXTURE/tmp/archmnt/usr/lib/firmware/qca/$name" "$FIXTURE/blobs/r8s-device/vendor/root/firmware/$name" || exit 40
done
printf new-image > "${@: -1}"
''', True)
        self.put("bin/e2fsck", '#!/bin/sh\n[ "${FAIL_AT:-}" != fsck ]\n', True)

    def assert_previous_rootfs_preserved(self):
        for name in ("ufs-root.img", "ufs-root.sha256", "arch-base-packages.txt"):
            self.assertEqual((self.root / "out/rootfs" / name).read_text(), "previous-good-artifact")

    def test_install_failure_preserves_image_and_busy_mount_tree(self):
        self.prepare_arch_build()
        self.env["FAIL_AT"] = "install"
        result = self.run_recipe("build-arch-rootfs.sh", "")
        self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
        self.assertTrue((self.root / "tmp/archmnt/dev/host-sentinel").exists(),
                        "cleanup traversed a tree whose unmount failed")
        self.assert_previous_rootfs_preserved()

    def test_fsck_failure_preserves_previous_image_and_manifests(self):
        self.prepare_arch_build()
        self.env["FAIL_AT"] = "fsck"
        result = self.run_recipe("build-arch-rootfs.sh", "")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Target rootfs tree size", result.stdout, result.stderr)
        self.assert_previous_rootfs_preserved()

    def test_success_publishes_verified_image_and_bluetooth(self):
        self.prepare_arch_build()
        result = self.run_recipe("build-arch-rootfs.sh", "")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        image = self.root / "out/rootfs/ufs-root.img"
        self.assertEqual(image.read_bytes(), b"new-image")
        manifest = (self.root / "out/rootfs/ufs-root.sha256").read_text()
        self.assertIn(hashlib.sha256(image.read_bytes()).hexdigest(), manifest)
        self.assertIn("ufs-root.img", manifest)
        self.assertEqual((self.root / "out/rootfs/arch-base-packages.txt").read_text(), "base 1\n")


if __name__ == "__main__":
    unittest.main()
