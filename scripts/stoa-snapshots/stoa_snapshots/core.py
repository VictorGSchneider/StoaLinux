"""Snapshot data for the Stoa snapshot browser — no GTK in here.

Two kinds of snapshot exist on a Stoa system, and this module is the one
place that knows how to read them:

* Package snapshots, written by scripts/stoa-pkg-snapshot.sh before every
  pacman transaction: ~/.config/stoa/pkg-snapshots/pkg-snapshot-<stamp>.txt,
  a few "# key: value" header lines followed by `pacman -Q` output
  ("name version" per line).

* Config backups, written by `stoa-maintain --backup`:
  $XDG_STATE_HOME/stoa/backups/<host>.confs.<YYYYMMDD>.zip, holding files
  under their absolute path minus the leading "/" (etc/fstab,
  home/<user>/.bashrc). Before a restore, stoa-maintain also saves the
  files it is about to overwrite as pre_restore_<stamp>.zip — a "safety"
  backup here.

Everything the UI shows is computed here so it can be tested without a
display, and so `stoa-snapshots summary` can feed the stoa-health panel
the same numbers the browser shows.
"""

from __future__ import annotations

import difflib
import os
import re
import shutil
import subprocess
import tempfile
import time
import zipfile
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


# ── Where things live ─────────────────────────────────────────────────


def pkg_snapshot_dir() -> Path:
    # stoa-pkg-snapshot.sh hard-codes ~/.config (it runs as root from the
    # pacman hook, where XDG_CONFIG_HOME means nothing), so do the same.
    return Path.home() / ".config" / "stoa" / "pkg-snapshots"


def backup_dir() -> Path:
    # Same definition as scripts/lib/stoa-paths.sh.
    state = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(state) / "stoa" / "backups"


# ── pacman version comparison ─────────────────────────────────────────
#
# Port of libalpm's alpm_pkg_vercmp (rpmvercmp + epoch/release), so that a
# version change is labelled upgrade or downgrade the way pacman itself
# would — a plain string compare calls 1.10 older than 1.9.



def _rpmvercmp(a: str, b: str) -> int:
    # Line-for-line with rpmvercmp() in lib/libalpm/version.c; indices
    # stand in for its char pointers. pacman's own test suite
    # (test/util/vercmptest.sh) is replayed in tests/test_stoa_snapshots.sh.
    if a == b:
        return 0
    one = two = 0          # start of the current segment
    p1 = p2 = 0            # end of the previous segment
    while one < len(a) and two < len(b):
        while one < len(a) and not a[one].isalnum():
            one += 1
        while two < len(b) and not b[two].isalnum():
            two += 1
        if not (one < len(a) and two < len(b)):
            break
        # separator runs of different length decide it
        if (one - p1) != (two - p2):
            return -1 if (one - p1) < (two - p2) else 1
        p1, p2 = one, two
        isnum = a[p1].isdigit()
        if isnum:
            while p1 < len(a) and a[p1].isdigit():
                p1 += 1
            while p2 < len(b) and b[p2].isdigit():
                p2 += 1
        else:
            while p1 < len(a) and a[p1].isalpha():
                p1 += 1
            while p2 < len(b) and b[p2].isalpha():
                p2 += 1
        if two == p2:
            # different segment types: numeric is always newer than alpha
            return 1 if isnum else -1
        s1, s2 = a[one:p1], b[two:p2]
        if isnum:
            s1, s2 = s1.lstrip("0"), s2.lstrip("0")
            if len(s1) != len(s2):
                return 1 if len(s1) > len(s2) else -1
        if s1 != s2:
            return 1 if s1 > s2 else -1
        one, two = p1, p2
    rest1, rest2 = a[one:], b[two:]
    if not rest1 and not rest2:
        return 0
    # A remaining alpha string never beats an empty one (1.0rc1 < 1.0).
    if (not rest1 and not rest2[:1].isalpha()) or rest1[:1].isalpha():
        return -1
    return 1


def _split_evr(v: str) -> tuple[str, str, str]:
    epoch, _, rest = v.partition(":") if ":" in v else ("0", "", v)
    if not epoch.isdigit():
        epoch, rest = "0", v
    ver, _, rel = rest.rpartition("-") if "-" in rest else (rest, "", "")
    return epoch, ver, rel


def vercmp(a: str, b: str) -> int:
    """-1 if a is older than b, 0 if equal, 1 if newer (pacman's rules)."""
    if a == b:
        return 0
    e1, v1, r1 = _split_evr(a)
    e2, v2, r2 = _split_evr(b)
    for x, y in ((e1, e2), (v1, v2)):
        c = _rpmvercmp(x, y)
        if c:
            return c
    if r1 and r2:
        return _rpmvercmp(r1, r2)
    return 0


# ── Package snapshots ─────────────────────────────────────────────────

_STAMP = re.compile(r"(\d{8})[-_](\d{6})")


def _stamp_time(name: str, fallback: float) -> datetime:
    m = _STAMP.search(name)
    if m:
        try:
            return datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
        except ValueError:
            pass
    return datetime.fromtimestamp(fallback)


@dataclass
class PkgSnapshot:
    path: Path
    taken: datetime
    packages: dict[str, str]
    explicit: int | None = None   # from the header; not derivable from -Q
    foreign: int | None = None

    @property
    def total(self) -> int:
        return len(self.packages)


def parse_pkg_snapshot(path: Path) -> PkgSnapshot:
    packages: dict[str, str] = {}
    header: dict[str, str] = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                key, sep, value = line.lstrip("# ").partition(":")
                if sep:
                    header[key.strip().lower()] = value.strip()
                continue
            name, _, version = line.partition(" ")
            if name and version:
                packages[name] = version.strip()

    def _int(key: str) -> int | None:
        try:
            return int(header.get(key, ""))
        except ValueError:
            return None

    return PkgSnapshot(
        path=path,
        taken=_stamp_time(path.name, path.stat().st_mtime),
        packages=packages,
        explicit=_int("explicit"),
        foreign=_int("aur/foreign"),
    )


def list_pkg_snapshots(directory: Path | None = None) -> list[PkgSnapshot]:
    """Newest first."""
    directory = directory or pkg_snapshot_dir()
    if not directory.is_dir():
        return []
    snaps = []
    for p in directory.glob("pkg-snapshot-*.txt"):
        try:
            snaps.append(parse_pkg_snapshot(p))
        except OSError:
            continue
    return sorted(snaps, key=lambda s: s.taken, reverse=True)


def current_packages() -> dict[str, str] | None:
    """`pacman -Q` right now, or None where there is no pacman."""
    try:
        out = subprocess.run(["pacman", "-Q"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    pkgs = {}
    for line in out.splitlines():
        name, _, version = line.partition(" ")
        if name and version:
            pkgs[name] = version
    return pkgs


@dataclass
class PkgDiff:
    added: list[tuple[str, str]] = field(default_factory=list)
    removed: list[tuple[str, str]] = field(default_factory=list)
    upgraded: list[tuple[str, str, str]] = field(default_factory=list)
    downgraded: list[tuple[str, str, str]] = field(default_factory=list)

    @property
    def empty(self) -> bool:
        return not (self.added or self.removed or self.upgraded or self.downgraded)

    def short(self) -> str:
        """"↑12 +3 −1" — the counts that are not zero."""
        parts = []
        if self.upgraded:
            parts.append(f"↑{len(self.upgraded)}")
        if self.downgraded:
            parts.append(f"↓{len(self.downgraded)}")
        if self.added:
            parts.append(f"+{len(self.added)}")
        if self.removed:
            parts.append(f"−{len(self.removed)}")
        return " ".join(parts) or "no changes"


def diff_packages(old: dict[str, str], new: dict[str, str]) -> PkgDiff:
    """What changed going from `old` to `new`, each list sorted by name."""
    d = PkgDiff()
    for name in sorted(old.keys() | new.keys()):
        a, b = old.get(name), new.get(name)
        if a is None:
            d.added.append((name, b))
        elif b is None:
            d.removed.append((name, a))
        elif a != b:
            (d.upgraded if vercmp(b, a) > 0 else d.downgraded).append((name, a, b))
    return d


# ── Config backups ────────────────────────────────────────────────────


@dataclass
class ConfigBackup:
    path: Path
    taken: datetime
    size: int
    safety: bool   # pre_restore_*.zip: what a restore overwrote

    @property
    def title(self) -> str:
        return "Before a restore" if self.safety else "Config backup"


def list_config_backups(directory: Path | None = None) -> list[ConfigBackup]:
    """Newest first. A day's backup is updated in place, so its time is
    the archive's mtime, not the date in its name."""
    directory = directory or backup_dir()
    if not directory.is_dir():
        return []
    out = []
    for p in list(directory.glob("*.confs.*.zip")) + list(directory.glob("pre_restore_*.zip")):
        try:
            st = p.stat()
        except OSError:
            continue
        out.append(ConfigBackup(
            path=p,
            taken=datetime.fromtimestamp(st.st_mtime),
            size=st.st_size,
            safety=p.name.startswith("pre_restore_"),
        ))
    return sorted(out, key=lambda b: b.taken, reverse=True)


# Status of a backed-up file compared with the file on disk now.
SAME, CHANGED, MISSING, UNREADABLE = "same", "changed", "missing", "unreadable"


@dataclass
class BackupEntry:
    member: str      # name inside the zip: "etc/fstab"
    path: Path       # where it came from: /etc/fstab
    size: int
    mode: int        # unix permission bits stored in the zip, 0 if none
    status: str = ""


def _member_mode(info: zipfile.ZipInfo) -> int:
    return (info.external_attr >> 16) & 0o7777


def backup_entries(backup: Path, with_status: bool = True) -> list[BackupEntry]:
    entries = []
    with zipfile.ZipFile(backup) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            e = BackupEntry(
                member=info.filename,
                path=Path("/" + info.filename.lstrip("/")),
                size=info.file_size,
                mode=_member_mode(info),
            )
            if with_status:
                e.status = _status(zf, e)
            entries.append(e)
    return sorted(entries, key=lambda e: str(e.path))


def count_files(backup: Path) -> int:
    """Files in a backup (the zip's index only — cheap); -1 if unreadable."""
    try:
        with zipfile.ZipFile(backup) as zf:
            return sum(1 for i in zf.infolist() if not i.is_dir())
    except (OSError, zipfile.BadZipFile):
        return -1


def _status(zf: zipfile.ZipFile, e: BackupEntry) -> str:
    try:
        if not e.path.exists():
            return MISSING
        if e.path.stat().st_size != e.size:
            return CHANGED
        current = e.path.read_bytes()
    except PermissionError:
        return UNREADABLE
    except OSError:
        return MISSING
    return SAME if current == zf.read(e.member) else CHANGED


def read_member(backup: Path, member: str) -> bytes:
    with zipfile.ZipFile(backup) as zf:
        return zf.read(member)


def is_text(data: bytes) -> bool:
    if b"\0" in data[:8192]:
        return False
    try:
        data[:8192].decode("utf-8")
    except UnicodeDecodeError:
        return False
    return True


def text_diff(saved: bytes, current: bytes, path: str) -> list[str]:
    """Unified diff from the backed-up copy to the file as it is now.

    Read as "what changed since the backup": '-' lines are what the backup
    had, '+' lines are what is there today.
    """
    a = saved.decode("utf-8", errors="replace").splitlines()
    b = current.decode("utf-8", errors="replace").splitlines()
    return list(difflib.unified_diff(a, b, f"backup: {path}", f"now: {path}", lineterm=""))


def group_of(path: Path) -> str:
    """Section the browser lists a file under: "~", "/etc", "/boot"…"""
    home = str(Path.home())
    s = str(path)
    if s == home or s.startswith(home + "/"):
        return "~"
    parts = path.parts
    return "/" + parts[1] if len(parts) > 2 else "/"


def display_path(path: Path) -> str:
    home = str(Path.home())
    s = str(path)
    return "~" + s[len(home):] if s.startswith(home + "/") else s


# ── Restoring one file ────────────────────────────────────────────────


def needs_privilege(path: Path) -> bool:
    """True when this user cannot write `path` (or create it) directly."""
    target = path if path.exists() else path.parent
    while not target.exists() and target != target.parent:
        target = target.parent
    return not os.access(target, os.W_OK)


def safety_backup(paths: list[Path], directory: Path | None = None) -> Path | None:
    """Copy what is on disk now into pre_restore_<stamp>.zip, the same
    safety net stoa-maintain makes before a restore. Unreadable or missing
    files are skipped; returns None when nothing was saved."""
    directory = directory or backup_dir()
    readable = [p for p in paths if p.is_file() and os.access(p, os.R_OK)]
    if not readable:
        return None
    directory.mkdir(parents=True, exist_ok=True)
    out = directory / f"pre_restore_{time.strftime('%Y%m%d_%H%M%S')}.zip"
    with zipfile.ZipFile(out, "a", zipfile.ZIP_DEFLATED) as zf:
        for p in readable:
            zf.write(p, str(p).lstrip("/"))
    return out


def restore_entry(backup: Path, entry: BackupEntry, run=subprocess.run,
                  safety_dir: Path | None = None) -> Path | None:
    """Put the backed-up copy of one file back where it came from.

    Saves the current file first (returns that safety zip, or None when
    there was nothing to save). Files this user cannot write go through
    pkexec — the same graphical prompt the stoa-health buttons use.
    Raises RuntimeError when the privileged copy fails or is cancelled.
    """
    data = read_member(backup, entry.member)
    saved = safety_backup([entry.path], safety_dir)
    mode = entry.mode or 0o644

    if not needs_privilege(entry.path):
        entry.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = entry.path.with_name(f".{entry.path.name}.stoa-restore")
        tmp.write_bytes(data)
        os.chmod(tmp, mode)
        os.replace(tmp, entry.path)
        return saved

    with tempfile.NamedTemporaryFile(delete=False, prefix="stoa-restore-") as fh:
        fh.write(data)
        tmp_path = fh.name
    try:
        # install(1) keeps an existing file's owner when run as root and
        # creates the parent directories; -m restores the saved mode.
        result = run(["pkexec", "install", "-D", "-m", f"{mode:o}", tmp_path, str(entry.path)])
        if getattr(result, "returncode", 1) != 0:
            raise RuntimeError(f"Restoring {entry.path} was cancelled or failed")
    finally:
        os.unlink(tmp_path)
    return saved


# ── Summary for the stoa-health panel ─────────────────────────────────


def plural(n: int, word: str) -> str:
    return f"{n} {word}" if n == 1 else f"{n} {word}s"


def human_size(n: int) -> str:
    size = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{n} B"


def when(dt: datetime, now: datetime | None = None) -> str:
    """"today 14:02", "yesterday 09:15", "18 Oct 09:00", "18 Oct 2025"."""
    now = now or datetime.now()
    days = (now.date() - dt.date()).days
    if days == 0:
        return f"today {dt:%H:%M}"
    if days == 1:
        return f"yesterday {dt:%H:%M}"
    if dt.year == now.year:
        return f"{dt:%d %b %H:%M}"
    return f"{dt:%d %b %Y}"


def summary() -> dict:
    """What the stoa-health panel prints above its buttons."""
    pkgs = list_pkg_snapshots()
    cfgs = [b for b in list_config_backups() if not b.safety]
    out = {
        "packages": {"count": len(pkgs), "latest": "", "latestChanges": ""},
        "configs": {"count": len(cfgs), "latest": "", "latestFiles": 0},
    }
    if pkgs:
        out["packages"]["latest"] = when(pkgs[0].taken)
        if len(pkgs) > 1:
            out["packages"]["latestChanges"] = diff_packages(pkgs[1].packages, pkgs[0].packages).short()
    if cfgs:
        out["configs"]["latest"] = when(cfgs[0].taken)
        out["configs"]["latestFiles"] = max(count_files(cfgs[0].path), 0)
    return out


def which(name: str) -> str | None:
    """A Stoa command: ~/.local/bin first (the session PATH may lack it)."""
    local = Path.home() / ".local" / "bin" / name
    if local.exists():
        return str(local)
    return shutil.which(name)
