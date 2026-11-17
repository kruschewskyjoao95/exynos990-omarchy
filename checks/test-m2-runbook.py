#!/usr/bin/env python3
"""Check the M2 runbook stays complete (files, hashes, getprop, serial, rollback)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class M2Runbook(unittest.TestCase):
    def test_runbook(self):
        text = (ROOT / "manifests" / "m2-runbook.md").read_text()
        for marker in ("cd727178", "fe07490f", "a2bcc167", "d999b844",
                       "SM-G780F", "ro.product.model", "ro.product.device",
                       "lk3rd-r8s.tar", "fastboot boot", "/dev/ttyACM",
                       "sda13", "sda32", "stock-backup-verify.txt"):
            self.assertIn(marker, text)

    def test_containers_review(self):
        text = (ROOT / "manifests" / "m1-containers-review.md").read_text()
        for marker in ("build-arch-rootfs.sh", "losetup", "/dev/sda32",
                       "r8s-serial.py", "validate-arm64-userspace.sh"):
            self.assertIn(marker, text)


if __name__ == "__main__":
    unittest.main()
