#!/usr/bin/env python3
"""Unit tests for scripts/stoa-hardware.py.

evaluate() is pure (collected data in, findings out), so the thresholds are
tested directly; the collectors run against a fake sysfs/procfs tree; the
slow-probe cache is tested by counting calls. Nothing here touches the real
machine, udisks2 or the journal.
"""

import importlib.util
import json
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("stoa_hardware", ROOT / "scripts" / "stoa-hardware.py")
hw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hw)


def nvme_smart(**kw):
    s = {"kind": "nvme", "criticalWarning": [], "powerOnHours": 100, "tempC": 35,
         "selftest": "success", "percentUsed": 1, "availSpare": 100, "spareThreshold": 10,
         "mediaErrors": 0, "errorLogEntries": 0, "unsafeShutdowns": 3, "powerCycles": 9,
         "writtenBytes": 1_000_000_000_000, "warnTempC": 75, "critTempC": 80,
         "warnTempMinutes": 0, "critTempMinutes": 0}
    s.update(kw)
    return s


def machine(**over):
    """A healthy laptop; tests override one part at a time."""
    d = {
        "storage": {"drives": [{"name": "nvme0", "kind": "nvme", "model": "Test SSD", "serial": "X",
                                "tempC": 35.0, "smart": nvme_smart(), "smartAvailable": True}],
                    "filesystems": []},
        "memory": {"totalGiB": 16.0, "swapUsedPct": 4.0, "pressureSome": 0.0, "pressureFull": 0.0,
                   "edac": False, "ecCorrected": 0, "ecUncorrected": 0, "dimmTempsC": [40.0]},
        "cpu": {"model": "Test CPU", "threads": 16, "online": 16, "tempC": 45.0, "throttleEvents": 0},
        "gpus": [{"name": "Test GPU", "vendor": "nvidia", "state": "active", "tempC": 40.0,
                  "busyPct": 1.0, "vramUsedMiB": 10, "vramTotalMiB": 6000, "thermalSlowdown": False}],
        "display": {"connectors": [{"name": "eDP-1", "status": "connected", "enabled": True,
                                    "mode": "1920x1080", "internal": True}],
                    "backlight": {"name": "bl", "pct": 80}},
        "battery": {"name": "BAT1", "status": "Charging", "capacityPct": 50, "level": "Normal",
                    "healthPct": 94.0, "cycles": None, "acOnline": True},
        "kernel": {"counts": {k: 0 for k, *_ in hw.JOURNAL_RULES}, "samples": {}},
    }
    for k, v in over.items():
        d[k] = v
    return d


def levels(d):
    return {(f["area"], f["level"]) for f in hw.evaluate(d)}


def only_bad(d):
    return [f for f in hw.evaluate(d) if f["level"] in ("warn", "fail")]


class Evaluate(unittest.TestCase):
    def test_healthy_machine_has_no_findings(self):
        self.assertEqual(only_bad(machine()), [])
        self.assertEqual(hw.tally(hw.evaluate(machine())), (0, 0))

    def test_nvme_critical_warning_fails(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(criticalWarning=["spare"])
        self.assertIn(("storage", "fail"), levels(d))

    def test_nvme_spare_at_threshold_fails(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(availSpare=10, spareThreshold=10)
        self.assertIn(("storage", "fail"), levels(d))

    def test_nvme_wear_bands(self):
        for used, want in ((79, None), (80, "warn"), (89, "warn"), (90, "fail"), (100, "fail")):
            d = machine()
            d["storage"]["drives"][0]["smart"] = nvme_smart(percentUsed=used)
            bad = only_bad(d)
            self.assertEqual(bad[0]["level"] if bad else None, want, used)

    def test_nvme_media_errors_fail(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(mediaErrors=2)
        self.assertIn(("storage", "fail"), levels(d))

    def test_lifetime_temp_minutes_are_noise_until_sustained(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(warnTempMinutes=1)
        self.assertEqual(only_bad(d), [])
        d["storage"]["drives"][0]["smart"] = nvme_smart(warnTempMinutes=45)
        self.assertIn(("storage", "warn"), levels(d))
        d["storage"]["drives"][0]["smart"] = nvme_smart(critTempMinutes=1)
        self.assertIn(("storage", "warn"), levels(d))

    def test_nvme_temperature_limits(self):
        d = machine()
        d["storage"]["drives"][0]["tempC"] = 76.0
        self.assertIn(("storage", "warn"), levels(d))
        d["storage"]["drives"][0]["tempC"] = 80.0
        self.assertIn(("storage", "fail"), levels(d))

    def test_failed_selftest_warns_but_running_one_does_not(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(selftest="fatal_error")
        self.assertIn(("storage", "warn"), levels(d))
        d["storage"]["drives"][0]["smart"] = nvme_smart(selftest="inprogress")
        self.assertEqual(only_bad(d), [])

    def test_missing_smart_is_info_not_a_problem(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = None
        d["storage"]["drives"][0]["smartAvailable"] = False
        self.assertEqual(only_bad(d), [])
        self.assertIn(("storage", "info"), levels(d))

    def test_ata_failing_and_bad_sectors(self):
        ata = {"kind": "ata", "failing": True, "badSectors": 0, "attrsFailing": 0,
               "powerOnHours": 5, "tempC": 30, "selftest": "success"}
        d = machine()
        d["storage"]["drives"] = [{"name": "sda", "kind": "ata", "model": "Disk", "serial": "S",
                                   "tempC": 30, "smart": ata, "smartAvailable": True}]
        self.assertIn(("storage", "fail"), levels(d))
        ata.update(failing=False, badSectors=8)
        self.assertIn(("storage", "warn"), levels(d))

    def test_btrfs_errors_fail_and_clean_is_ok(self):
        d = machine()
        d["storage"]["filesystems"] = [{"fs": "btrfs", "label": "root", "errors": {"corruption_errs": 3}, "total": 3}]
        self.assertIn(("storage", "fail"), levels(d))
        d["storage"]["filesystems"] = [{"fs": "btrfs", "label": "root", "errors": {"read_errs": 0}, "total": 0}]
        self.assertEqual(only_bad(d), [])

    def test_memory(self):
        d = machine()
        d["memory"]["ecUncorrected"] = 1
        self.assertIn(("memory", "fail"), levels(d))
        d = machine()
        d["memory"]["ecCorrected"] = 4
        self.assertIn(("memory", "warn"), levels(d))
        d = machine()
        d["memory"]["swapUsedPct"] = 85
        self.assertIn(("memory", "warn"), levels(d))
        d = machine()
        d["memory"]["pressureFull"] = 12
        self.assertIn(("memory", "warn"), levels(d))
        d = machine()
        d["memory"]["dimmTempsC"] = [96.0]
        self.assertIn(("memory", "fail"), levels(d))

    def test_cpu(self):
        for temp, want in ((89, None), (90, "warn"), (100, "fail")):
            d = machine()
            d["cpu"]["tempC"] = temp
            bad = only_bad(d)
            self.assertEqual(bad[0]["level"] if bad else None, want, temp)
        d = machine()
        d["cpu"]["online"] = 14
        self.assertIn(("cpu", "warn"), levels(d))
        d = machine()
        d["cpu"]["throttleEvents"] = 3
        self.assertIn(("cpu", "warn"), levels(d))

    def test_gpu(self):
        d = machine()
        d["gpus"][0]["tempC"] = 86
        self.assertIn(("gpu", "warn"), levels(d))
        d["gpus"][0]["tempC"] = 95
        self.assertIn(("gpu", "fail"), levels(d))
        d = machine()
        d["gpus"][0]["thermalSlowdown"] = True
        self.assertIn(("gpu", "warn"), levels(d))

    def test_sleeping_gpu_is_fine_and_not_probed(self):
        d = machine()
        d["gpus"][0].update(state="asleep", tempC=None, busyPct=None)
        self.assertEqual(only_bad(d), [])

    def test_internal_panel(self):
        d = machine()
        d["display"]["connectors"][0]["status"] = "disconnected"
        self.assertIn(("display", "fail"), levels(d))
        d = machine()
        d["display"]["connectors"][0]["enabled"] = False
        self.assertIn(("display", "warn"), levels(d))

    def test_external_display_is_never_a_problem(self):
        d = machine()
        d["display"]["connectors"].append({"name": "HDMI-A-1", "status": "connected", "enabled": False,
                                           "mode": None, "internal": False})
        self.assertEqual(only_bad(d), [])

    def test_no_internal_panel_is_not_a_problem(self):
        d = machine()
        d["display"]["connectors"] = []
        self.assertEqual(only_bad(d), [])

    def test_battery_wear(self):
        for health, want in ((94, None), (80, None), (79, "warn"), (60, "warn"), (59, "fail")):
            d = machine()
            d["battery"]["healthPct"] = health
            bad = only_bad(d)
            self.assertEqual(bad[0]["level"] if bad else None, want, health)
        d = machine(battery=None)
        self.assertEqual(only_bad(d), [])

    def test_kernel_log(self):
        d = machine()
        d["kernel"]["counts"]["io"] = 3
        d["kernel"]["samples"]["io"] = "Buffer I/O error"
        self.assertIn(("storage", "fail"), levels(d))
        d = machine()
        d["kernel"]["counts"]["oom"] = 1
        self.assertIn(("memory", "warn"), levels(d))

    def test_unreadable_kernel_log_is_info_not_all_clear(self):
        d = machine(kernel=None)
        self.assertEqual(only_bad(d), [])
        self.assertIn(("kernel", "info"), levels(d))
        self.assertNotIn(("kernel", "ok"), levels(d))

    def test_tally_counts_fail_and_warn_only(self):
        d = machine()
        d["storage"]["drives"][0]["smart"] = nvme_smart(mediaErrors=1, percentUsed=85)
        d["cpu"]["throttleEvents"] = 1
        self.assertEqual(hw.tally(hw.evaluate(d)), (1, 2))


class Classify(unittest.TestCase):
    def test_real_errors_match(self):
        cases = {
            "Buffer I/O error on dev nvme0n1p2, logical block 5, async page read": "io",
            "nvme nvme0: I/O 12 QID 3 timeout, reset controller": "nvme",
            "EXT4-fs error (device nvme0n1p2): ext4_find_entry:1455": "fs",
            "BTRFS error (device nvme0n1p2): bdev /dev/nvme0n1p2 errs: wr 0, rd 1": "fs",
            "mce: [Hardware Error]: Machine check events logged": "mce",
            "pcieport 0000:00:01.1: AER: Corrected error message received": "pcie",
            "NVRM: Xid (PCI:0000:01:00): 79, GPU has fallen off the bus.": "gpu_lost",
            "NVRM: Xid (PCI:0000:01:00): 31, pid=1, Ch 00000008": "gpu_nv",
            "amdgpu 0000:75:00.0: amdgpu: ring gfx_0.0.0 timeout, signaled seq=1": "gpu_amd",
            "[drm:dc_link_dp_trace] flip_done timed out": "display",
            "Out of memory: Killed process 4242 (firefox) total-vm:1kB": "oom",
        }
        for line, key in cases.items():
            self.assertIn(key, hw.classify(line), line)

    def test_boot_noise_does_not_match(self):
        for line in ("nvme nvme0: 16/0/0 default/read/poll queues",
                     "virt/tdx: TDX not supported by the host platform",
                     "ACPI: \\_SB_.PCI0.GP11: Overriding _PRW sleep state (S4) by S0",
                     "EXT4-fs (nvme0n1p2): mounted filesystem with ordered data mode",
                     "amdgpu 0000:75:00.0: amdgpu: SMU is initialized successfully!",
                     "BTRFS info (device nvme0n1p2): using crc32c checksum algorithm"):
            self.assertEqual(hw.classify(line), [], line)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class FakeMachine(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.old = (hw.SYS, hw.PROC, hw.run, hw.have)
        hw.SYS, hw.PROC = self.root / "sys", self.root / "proc"
        self.calls = []

        def fake_run(cmd, timeout=15):
            self.calls.append(cmd[0])
            return -1, ""
        hw.run = fake_run
        hw.have = lambda b: True

    def tearDown(self):
        hw.SYS, hw.PROC, hw.run, hw.have = self.old
        self.tmp.cleanup()

    def test_nvme_is_matched_to_smart_by_stripped_serial(self):
        s = hw.SYS
        write(s / "class/nvme/nvme0/serial", "ABC123    \n")
        write(s / "class/nvme/nvme0/model", "Test   SSD  \n")
        write(s / "class/nvme/nvme0/state", "live\n")
        write(s / "class/nvme/nvme0/hwmon3/temp1_input", "36850\n")
        out = hw.collect_storage({"smart": {"ABC123": nvme_smart()}})
        d = out["drives"][0]
        self.assertEqual((d["model"], d["serial"], d["tempC"]), ("Test SSD", "ABC123", 36.9))
        self.assertEqual(d["smart"]["percentUsed"], 1)

    def test_smart_unavailable_is_flagged_not_hidden(self):
        write(hw.SYS / "class/nvme/nvme0/serial", "A\n")
        d = hw.collect_storage({"smart": None})["drives"][0]
        self.assertIsNone(d["smart"])
        self.assertFalse(d["smartAvailable"])

    def test_btrfs_error_stats_are_summed_per_filesystem(self):
        base = hw.SYS / "fs/btrfs/31a056bf-eaea-4d19-8ff1-3e45e4a14ed3"
        write(base / "label", "root\n")
        write(base / "devinfo/1/error_stats", "write_errs 0\nread_errs 2\nflush_errs 0\ncorruption_errs 1\ngeneration_errs 0\n")
        write(base / "devinfo/2/error_stats", "write_errs 0\nread_errs 1\nflush_errs 0\ncorruption_errs 0\ngeneration_errs 0\n")
        fs = hw.collect_storage({})["filesystems"]
        self.assertEqual(fs[0]["label"], "root")
        self.assertEqual(fs[0]["total"], 4)
        self.assertEqual(fs[0]["errors"]["read_errs"], 3)

    def test_memory(self):
        write(hw.PROC / "meminfo", "MemTotal: 16777216 kB\nSwapTotal: 8388608 kB\nSwapFree: 2097152 kB\n")
        write(hw.PROC / "pressure/memory", "some avg10=0.00 avg60=1.50 avg300=0.00 total=1\nfull avg10=0.00 avg60=11.25 avg300=0.00 total=1\n")
        write(hw.SYS / "devices/system/edac/mc/mc0/ce_count", "2\n")
        write(hw.SYS / "devices/system/edac/mc/mc0/ue_count", "0\n")
        m = hw.collect_memory()
        self.assertEqual(m["totalGiB"], 16.0)
        self.assertEqual(m["swapUsedPct"], 75.0)
        self.assertEqual((m["pressureSome"], m["pressureFull"]), (1.5, 11.25))
        self.assertTrue(m["edac"])
        self.assertEqual((m["ecCorrected"], m["ecUncorrected"]), (2, 0))

    def test_cpu_prefers_tctl_and_counts_threads(self):
        write(hw.PROC / "cpuinfo", "processor : 0\nmodel name : AMD Ryzen 7 7735HS with Radeon Graphics\n")
        write(hw.SYS / "devices/system/cpu/present", "0-15\n")
        write(hw.SYS / "devices/system/cpu/online", "0-13,15\n")
        write(hw.SYS / "class/hwmon/hwmon6/name", "k10temp\n")
        write(hw.SYS / "class/hwmon/hwmon6/temp1_input", "61000\n")
        write(hw.SYS / "class/hwmon/hwmon6/temp1_label", "Tctl\n")
        write(hw.SYS / "class/hwmon/hwmon6/temp3_input", "90000\n")
        write(hw.SYS / "class/hwmon/hwmon6/temp3_label", "Tccd1\n")
        write(hw.SYS / "devices/system/cpu/cpu0/thermal_throttle/core_throttle_count", "3\n")
        c = hw.collect_cpu()
        self.assertEqual((c["threads"], c["online"]), (16, 15))
        self.assertEqual(c["tempC"], 61.0)
        self.assertEqual(c["throttleEvents"], 3)
        self.assertNotIn("with Radeon", c["model"])

    def test_sleeping_nvidia_is_not_woken(self):
        dev = hw.SYS / "bus/pci/devices/0000:01:00.0"
        write(dev / "class", "0x030000\n")
        write(dev / "vendor", "0x10de\n")
        write(dev / "power/runtime_status", "suspended\n")
        g = hw.collect_gpus({"pciNames": {"0000:01:00.0": "NVIDIA GeForce"}})[0]
        self.assertEqual(g["state"], "asleep")
        self.assertNotIn("nvidia-smi", self.calls)

    def test_awake_nvidia_is_queried_and_sw_throttle_flag_ignored_when_cool(self):
        dev = hw.SYS / "bus/pci/devices/0000:01:00.0"
        write(dev / "class", "0x030000\n")
        write(dev / "vendor", "0x10de\n")
        write(dev / "power/runtime_status", "active\n")

        def fake_run(cmd, timeout=15):
            self.calls.append(cmd[0])
            return 0, "NVIDIA RTX, 38, 4, 13, 6141, Not Active, Active\n"
        hw.run = fake_run
        g = hw.collect_gpus({})[0]
        self.assertIn("nvidia-smi", self.calls)
        self.assertEqual(g["tempC"], 38.0)
        self.assertFalse(g["thermalSlowdown"])

    def test_amd_gpu_reads_hwmon(self):
        dev = hw.SYS / "bus/pci/devices/0000:75:00.0"
        write(dev / "class", "0x030000\n")
        write(dev / "vendor", "0x1002\n")
        write(dev / "hwmon/hwmon5/temp1_input", "38000\n")
        write(dev / "gpu_busy_percent", "7\n")
        g = hw.collect_gpus({})[0]
        self.assertEqual((g["vendor"], g["tempC"], g["busyPct"]), ("amd", 38.0, 7))

    def test_display_dedupes_connectors_and_skips_writeback(self):
        s = hw.SYS / "class/drm"
        write(s / "card2-eDP-1/status", "connected\n")
        write(s / "card2-eDP-1/enabled", "enabled\n")
        write(s / "card2-eDP-1/modes", "1920x1080\n1280x720\n")
        write(s / "card1-HDMI-A-1/status", "disconnected\n")
        write(s / "card2-HDMI-A-1/status", "connected\n")
        write(s / "card2-Writeback-1/status", "unknown\n")
        write(s / "card1-eDP-1/status", "disconnected\n")  # same name on the other card
        write(hw.SYS / "class/backlight/bl/brightness", "50\n")
        write(hw.SYS / "class/backlight/bl/max_brightness", "200\n")
        disp = hw.collect_display()
        names = [c["name"] for c in disp["connectors"]]
        self.assertEqual(sorted(names), ["HDMI-A-1", "eDP-1"])
        edp = next(c for c in disp["connectors"] if c["name"] == "eDP-1")
        self.assertTrue(edp["internal"] and edp["enabled"])
        self.assertEqual(edp["status"], "connected")
        self.assertEqual(edp["mode"], "1920x1080")
        self.assertEqual(disp["backlight"]["pct"], 25)

    def test_battery_health_from_charge_or_energy(self):
        b = hw.SYS / "class/power_supply/BAT1"
        write(b / "type", "Battery\n")
        write(b / "status", "Discharging\n")
        write(b / "capacity", "63\n")
        write(b / "charge_full", "3497000\n")
        write(b / "charge_full_design", "3733000\n")
        write(b / "cycle_count", "0\n")
        write(hw.SYS / "class/power_supply/ACAD/type", "Mains\n")
        write(hw.SYS / "class/power_supply/ACAD/online", "0\n")
        bat = hw.collect_battery()
        self.assertEqual(bat["healthPct"], 93.7)
        self.assertIsNone(bat["cycles"])   # 0 means "not reported"
        self.assertFalse(bat["acOnline"])

    def test_no_battery_on_a_desktop(self):
        self.assertIsNone(hw.collect_battery())


class SmartReport(unittest.TestCase):
    def test_one_pkexec_for_all_drives(self):
        cmd = hw.smart_report_cmd(["/dev/nvme0n1", "/dev/nvme1n1", "/dev/sda"])
        self.assertEqual(cmd[0], "pkexec")
        self.assertEqual(cmd.count("pkexec"), 1)
        self.assertEqual(cmd[-3:], ["/dev/nvme0n1", "/dev/nvme1n1", "/dev/sda"])

    def test_drives_are_arguments_not_shell_text(self):
        cmd = hw.smart_report_cmd(["/dev/x; reboot"])
        self.assertNotIn("reboot", cmd[3])     # the -c script never contains them
        self.assertEqual(cmd[-1], "/dev/x; reboot")


class SlowCache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old = (hw.CACHE, hw.collect_smart, hw.collect_journal, hw.pci_names)
        hw.CACHE = Path(self.tmp.name) / "stoa" / "hardware-slow.json"
        self.n = 0

        def smart():
            self.n += 1
            return {}
        hw.collect_smart = smart
        hw.collect_journal = lambda: None
        hw.pci_names = lambda: {}

    def tearDown(self):
        hw.CACHE, hw.collect_smart, hw.collect_journal, hw.pci_names = self.old
        self.tmp.cleanup()

    def test_probes_run_once_within_ttl(self):
        hw.slow()
        hw.slow()
        self.assertEqual(self.n, 1)

    def test_fresh_bypasses_cache(self):
        hw.slow()
        hw.slow(fresh=True)
        self.assertEqual(self.n, 2)

    def test_expired_cache_is_refreshed(self):
        hw.slow()
        data = json.loads(hw.CACHE.read_text())
        data["ts"] = time.time() - hw.SLOW_TTL - 1
        hw.CACHE.write_text(json.dumps(data))
        hw.slow()
        self.assertEqual(self.n, 2)

    def test_corrupt_cache_is_ignored(self):
        hw.CACHE.parent.mkdir(parents=True)
        hw.CACHE.write_text("{not json")
        hw.slow()
        self.assertEqual(self.n, 1)


if __name__ == "__main__":
    unittest.main()
