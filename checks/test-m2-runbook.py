#!/usr/bin/env python3
"""Check the M2 runbook stays complete (files, hashes, getprop, serial, rollback)."""
from pathlib import Path
import re
import shlex
import subprocess
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class M2Runbook(unittest.TestCase):
    def assert_safe_heimdall_command(self, text):
        commands = re.findall(r'`(heimdall flash[^`]+)`', text)
        self.assertEqual(len(commands), 1)
        self.assertEqual(shlex.split(commands[0]),
                         ["heimdall", "flash", "--BOOT", "out/boot/lk3rd-r8s.img", "--no-reboot"])

    def test_heimdall_uses_raw_image(self):
        self.assert_safe_heimdall_command((ROOT / "manifests/m2-runbook.md").read_text())

    def test_guard_rejects_archive_as_partition_image(self):
        for suffix in ("tar", "img.lz4"):
            with self.subTest(suffix=suffix), self.assertRaises(AssertionError):
                self.assert_safe_heimdall_command(
                    f"`heimdall flash --BOOT out/boot/lk3rd-r8s.{suffix} --no-reboot`")

    def test_odin_payload_matches_raw_heimdall_image(self):
        raw = (ROOT / "out/boot/lk3rd-r8s.img").read_bytes()
        self.assertTrue(raw.startswith(b"ANDROID!"))
        with tarfile.open(ROOT / "out/boot/lk3rd-r8s.tar") as archive:
            self.assertEqual(archive.getnames(), ["boot.img.lz4"])
            payload = archive.extractfile("boot.img.lz4").read()
        decoded = subprocess.run(["lz4", "-dc"], input=payload, capture_output=True, check=True).stdout
        self.assertEqual(decoded, raw)

    def test_runbook(self):
        text = (ROOT / "manifests" / "m2-runbook.md").read_text()
        for marker in ("cd727178", "fe07490f", "a2bcc167", "d999b844",
                       "SM-G780F", "ro.product.model", "ro.product.device",
                       "lk3rd-r8s.tar", "boot.img.lz4", "heimdall flash --BOOT",
                       "backup-manifest.sha256",
                       "fastboot boot", "/dev/ttyACM",
                       "sda13", "sda32", "stock-backup-verify.txt"):
            self.assertIn(marker, text)

    def test_containers_review(self):
        text = (ROOT / "manifests" / "m1-containers-review.md").read_text()
        for marker in ("build-arch-rootfs.sh", "losetup", "/dev/sda32",
                       "r8s-serial.py", "validate-arm64-userspace.sh"):
            self.assertIn(marker, text)


if __name__ == "__main__":
    unittest.main()
