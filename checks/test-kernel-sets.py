#!/usr/bin/env python3
"""Guard the baseline vs series sets so `out/boot/` stays the RAM-test set."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def config(path):
    return path.read_text()


class KernelSets(unittest.TestCase):
    def test_out_boot_is_baseline_for_first_ram_test(self):
        text = config(ROOT / "out" / "boot" / "kernel.config")
        self.assertIn('CONFIG_EXTRA_FIRMWARE=""', text)
        self.assertNotIn("CONFIG_DEVFREQ_THERMAL=y", text)

    def test_series_is_preserved_not_in_out_boot(self):
        preserved = ROOT / "out" / "validation" / "series-wifi" / "boot" / "kernel.config"
        self.assertTrue(preserved.is_file())
        self.assertIn("CONFIG_DEVFREQ_THERMAL=y", preserved.read_text())

    def test_series_list_order_and_exclusions(self):
        lines = [l.strip() for l in (ROOT / "packaging" / "kernel-patches" / "series").read_text().splitlines()]
        entries = [l for l in lines if l and not l.startswith("#")]
        self.assertTrue(entries[0].startswith("0100-"))
        self.assertFalse(any(l.startswith("0101-") for l in entries))
        self.assertFalse(any(l.startswith("0106-") for l in entries))


if __name__ == "__main__":
    unittest.main()
