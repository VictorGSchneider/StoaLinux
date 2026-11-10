#!/usr/bin/env python3
"""stoa-hardware must not wake a sleeping GPU to describe it.

The script says so itself, twice: a runtime-suspended NVIDIA card is
reported as "powered down (runtime PM), not woken to probe", and nvidia-smi
is skipped for it because "nvidia-smi would wake the card just to read a
temperature".

But every time the ten-minute cache expires, slow() also calls pci_names(),
and pci_names() runs `lspci` for the pretty device names. lspci reads PCI
config space, and the kernel resumes a D3cold device to answer that. Measured
on a hybrid laptop: runtime_status went suspended → active the moment lspci
ran, and stayed active for about 21 seconds — every ten minutes, for as long
as the health pill is on the bar. collect() then reads runtime_status, finds
the card it has just woken "active", and queries it with nvidia-smi as well.

The collectors run against a fake sysfs and a recording run(); nothing here
touches real hardware.
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "stoa_hardware", ROOT / "scripts" / "health" / "stoa-hardware.py")
hw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hw)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class SleepingGpu(unittest.TestCase):
    """A hybrid laptop: AMD iGPU awake, NVIDIA dGPU runtime-suspended."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.old = (hw.SYS, hw.PROC, hw.CACHE, hw.run, hw.have)
        hw.SYS, hw.PROC = root / "sys", root / "proc"
        hw.CACHE = root / "cache" / "hardware-slow.json"
        self.calls = []

        def fake_run(cmd, timeout=15):
            self.calls.append(cmd[0])
            return -1, ""

        hw.run = fake_run
        hw.have = lambda binary: True

        pci = hw.SYS / "bus/pci/devices"
        write(pci / "0000:05:00.0/class", "0x030000\n")
        write(pci / "0000:05:00.0/vendor", "0x1002\n")
        write(pci / "0000:05:00.0/power/runtime_status", "active\n")
        write(pci / "0000:01:00.0/class", "0x030000\n")
        write(pci / "0000:01:00.0/vendor", "0x10de\n")
        write(pci / "0000:01:00.0/power/runtime_status", "suspended\n")

    def tearDown(self):
        hw.SYS, hw.PROC, hw.CACHE, hw.run, hw.have = self.old
        self.tmp.cleanup()

    def test_cold_cache_runs_nothing_that_resumes_the_card(self):
        data = hw.collect(fresh=True)
        nvidia = [g for g in data["gpus"] if g.get("vendor") == "nvidia"]
        self.assertEqual(len(nvidia), 1)
        self.assertEqual(nvidia[0]["state"], "asleep")
        self.assertNotIn(
            "nvidia-smi", self.calls,
            "nvidia-smi was run against a runtime-suspended card")
        self.assertNotIn(
            "lspci", self.calls,
            "lspci reads PCI config space, which resumes a runtime-suspended GPU — "
            "take the device names from somewhere that does not (sysfs ids + hwdata, "
            "or a cache that outlives the ten-minute one)")

    def test_report_still_says_it_was_not_woken(self):
        findings = hw.evaluate({**hw.collect(fresh=True), "kernel": None})
        self.assertTrue(
            any("not woken to probe" in f["msg"] for f in findings),
            "the sleeping card should be reported as left asleep")


if __name__ == "__main__":
    unittest.main()
