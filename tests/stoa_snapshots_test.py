"""Unit tests for scripts/stoa-snapshots/stoa_snapshots/core.py.

Run by tests/test_stoa_snapshots.sh (so tests/run.sh and CI pick it up).
No GTK: core.py is everything the browser shows, computed without a
display. Each test gets its own fake $HOME.
"""

import os
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts" / "stoa-snapshots"))

from stoa_snapshots import core  # noqa: E402


class VercmpTest(unittest.TestCase):
    def test_pacman_suite(self):
        """Every case of pacman's vercmptest.sh, both directions."""
        cases = 0
        for line in (ROOT / "tests" / "fixtures" / "vercmp_cases.txt").read_text().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            a, b, want = line.split()
            want = int(want)
            self.assertEqual(core.vercmp(a, b), want, f"vercmp({a}, {b})")
            self.assertEqual(core.vercmp(b, a), -want, f"vercmp({b}, {a})")
            cases += 1
        self.assertGreaterEqual(cases, 40)

    def test_numeric_not_lexical(self):
        self.assertEqual(core.vercmp("1.10-1", "1.9-1"), 1)


class Home(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {"HOME": str(self.home), "XDG_STATE_HOME": ""})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def pkg_snapshot(self, stamp, pkgs, explicit=10, foreign=2):
        d = self.home / ".config" / "stoa" / "pkg-snapshots"
        d.mkdir(parents=True, exist_ok=True)
        p = d / f"pkg-snapshot-{stamp}.txt"
        lines = [f"# Stoa Package Snapshot — {stamp}", f"# Total packages: {len(pkgs)}",
                 f"# Explicit: {explicit}", f"# AUR/foreign: {foreign}", "#"]
        lines += [f"{n} {v}" for n, v in pkgs.items()]
        p.write_text("\n".join(lines) + "\n")
        return p

    def backup(self, name, files, mtime=None):
        d = self.home / ".local" / "state" / "stoa" / "backups"
        d.mkdir(parents=True, exist_ok=True)
        p = d / name
        with zipfile.ZipFile(p, "w") as zf:
            for path, (data, mode) in files.items():
                zi = zipfile.ZipInfo(str(path).lstrip("/"))
                zi.external_attr = (0o100000 | mode) << 16
                zf.writestr(zi, data)
        if mtime:
            os.utime(p, (mtime, mtime))
        return p


class PackageTest(Home):
    def test_parse_reads_header_and_packages(self):
        p = self.pkg_snapshot("20261019-081402", {"linux": "6.11-1", "mesa": "1:24.2-1"}, 7, 3)
        s = core.parse_pkg_snapshot(p)
        self.assertEqual(s.packages, {"linux": "6.11-1", "mesa": "1:24.2-1"})
        self.assertEqual((s.total, s.explicit, s.foreign), (2, 7, 3))
        self.assertEqual(s.taken, datetime(2026, 10, 19, 8, 14, 2))

    def test_list_newest_first(self):
        self.pkg_snapshot("20261012-091500", {"a": "1"})
        self.pkg_snapshot("20261019-081402", {"a": "2"})
        self.pkg_snapshot("20261017-220311", {"a": "1"})
        self.assertEqual([s.taken.day for s in core.list_pkg_snapshots()], [19, 17, 12])

    def test_diff_classifies(self):
        old = {"same": "1-1", "up": "1.9-1", "down": "2:1-1", "gone": "1-1"}
        new = {"same": "1-1", "up": "1.10-1", "down": "1:9-1", "new": "0.1-1"}
        d = core.diff_packages(old, new)
        self.assertEqual(d.upgraded, [("up", "1.9-1", "1.10-1")])
        self.assertEqual(d.downgraded, [("down", "2:1-1", "1:9-1")])
        self.assertEqual(d.added, [("new", "0.1-1")])
        self.assertEqual(d.removed, [("gone", "1-1")])
        self.assertEqual(d.short(), "↑1 ↓1 +1 −1")
        self.assertTrue(core.diff_packages(old, old).empty)


class ConfigTest(Home):
    def test_entries_and_status(self):
        same = self.home / ".gitconfig"
        same.write_text("[user]\n")
        changed = self.home / ".bashrc"
        changed.write_text("export EDITOR=nvim\n")
        gone = self.home / ".config" / "old.conf"
        b = self.backup("h.confs.20261015.zip", {
            same: ("[user]\n", 0o644),
            changed: ("export EDITOR=vim\n", 0o600),
            gone: ("x=1\n", 0o644),
        })
        entries = {e.path: e for e in core.backup_entries(b)}
        self.assertEqual(entries[same].status, core.SAME)
        self.assertEqual(entries[changed].status, core.CHANGED)
        self.assertEqual(entries[gone].status, core.MISSING)
        self.assertEqual(entries[changed].mode, 0o600)
        self.assertEqual(core.count_files(b), 3)
        self.assertEqual(core.group_of(changed), "~")
        self.assertEqual(core.group_of(Path("/etc/fstab")), "/etc")
        self.assertEqual(core.display_path(changed), "~/.bashrc")

    def test_diff_reads_backup_to_now(self):
        lines = core.text_diff(b"a\nold\n", b"a\nnew\n", "~/.x")
        self.assertIn("-old", lines)
        self.assertIn("+new", lines)

    def test_safety_backups_are_marked_and_sorted(self):
        self.backup("h.confs.20261015.zip", {"/etc/a": ("1", 0o644)}, mtime=1_000_000)
        self.backup("pre_restore_20261016_101010.zip", {"/etc/a": ("0", 0o644)}, mtime=2_000_000)
        backups = core.list_config_backups()
        self.assertEqual([b.safety for b in backups], [True, False])

    def test_restore_own_file_keeps_a_safety_copy(self):
        target = self.home / ".bashrc"
        target.write_text("new\n")
        b = self.backup("h.confs.20261015.zip", {target: ("old\n", 0o600)})
        entry = next(e for e in core.backup_entries(b) if e.path == target)
        saved = core.restore_entry(b, entry, run=self.fail)  # must not escalate
        self.assertEqual(target.read_text(), "old\n")
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertIsNotNone(saved)
        with zipfile.ZipFile(saved) as zf:
            self.assertEqual(zf.read(str(target).lstrip("/")), b"new\n")

    def test_restore_unwritable_file_goes_through_pkexec(self):
        target = Path("/etc/stoa-test-never-exists/locale.conf")
        b = self.backup("h.confs.20261015.zip", {target: ("LANG=pt_BR.UTF-8\n", 0o644)})
        entry = core.backup_entries(b)[0]
        calls = []

        class Done:
            returncode = 0

        def run(cmd):
            calls.append(cmd)
            return Done()

        with mock.patch.object(core, "needs_privilege", return_value=True):
            core.restore_entry(b, entry, run=run)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][:5], ["pkexec", "install", "-D", "-m", "644"])
        self.assertEqual(calls[0][-1], str(target))

        class Cancelled:
            returncode = 126

        with mock.patch.object(core, "needs_privilege", return_value=True):
            with self.assertRaises(RuntimeError):
                core.restore_entry(b, entry, run=lambda cmd: Cancelled())


class SummaryTest(Home):
    def test_summary_for_the_health_panel(self):
        self.pkg_snapshot("20261017-220311", {"a": "1-1", "b": "1-1"})
        self.pkg_snapshot("20261019-081402", {"a": "2-1", "c": "1-1"})
        self.backup("h.confs.20261015.zip", {"/etc/a": ("1", 0o644), "/etc/b": ("2", 0o644)})
        self.backup("pre_restore_20261016_101010.zip", {"/etc/a": ("0", 0o644)})
        s = core.summary()
        self.assertEqual(s["packages"]["count"], 2)
        self.assertEqual(s["packages"]["latestChanges"], "↑1 +1 −1")
        self.assertEqual(s["configs"]["count"], 1)   # safety copies are not "backups"
        self.assertEqual(s["configs"]["latestFiles"], 2)

    def test_when(self):
        now = datetime(2026, 10, 19, 12, 0)
        self.assertEqual(core.when(datetime(2026, 10, 19, 8, 14), now), "today 08:14")
        self.assertEqual(core.when(datetime(2026, 10, 18, 9, 0), now), "yesterday 09:00")
        self.assertEqual(core.when(datetime(2025, 3, 2, 9, 0), now), "02 Mar 2025")


if __name__ == "__main__":
    unittest.main()
