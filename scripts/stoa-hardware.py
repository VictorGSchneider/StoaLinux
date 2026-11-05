#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Hardware health                                ║
# ║  "Mens sana in corpore sano." — Juvenal                      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# SSDs (NVMe/ATA SMART), memory, CPU, GPUs, display panel, battery and the
# kernel log, read without root:
#
#   * SMART comes from udisks2 over D-Bus. Reading it is allowed for the
#     active local session, so no password and no /dev access is needed.
#     Starting a self-test is not (auth_admin_keep): `smart-test` asks
#     polkit, which raises the usual password box.
#   * Everything else is sysfs / procfs.
#
# The expensive probes (SMART refresh, kernel log scan) are cached for ten
# minutes in ~/.cache/stoa/hardware-slow.json so the bar widget can poll
# every 30 s. The doctor passes --fresh to bypass the cache.
#
# All judgement lives in evaluate(): pure data in, findings out, which is
# what tests/stoa_hardware_test.py exercises.

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SYS = Path(os.environ.get("STOA_HW_SYS", "/sys"))
PROC = Path(os.environ.get("STOA_HW_PROC", "/proc"))
CACHE = (Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
         / "stoa" / "hardware-slow.json")
SLOW_TTL = 600

UDISKS = "org.freedesktop.UDisks2"
U_ROOT = "/org/freedesktop/UDisks2"
I_DRIVE = "org.freedesktop.UDisks2.Drive"
I_NVME = "org.freedesktop.UDisks2.NVMe.Controller"
I_ATA = "org.freedesktop.UDisks2.Drive.Ata"

HELP = """\
stoa-hardware — hardware health: SSD SMART, memory, CPU, GPUs, display, battery, kernel log.

USAGE
  stoa-hardware [COMMAND] [--fresh]

COMMANDS
  json                 everything as JSON (default)
  summary              same, without the passing checks (used by stoa-vitals-status)
  report               human-readable report
  doctor               one "LEVEL<TAB>message" line per check (used by stoa-doctor)
  smart-test [KIND] [DRIVE] [--notify]
                       start a SMART self-test through udisks2 and wait for it.
                       KIND is short (default) or extended; DRIVE is nvme0,
                       a serial or part of the model (default: every drive).
                       Asks for your password through polkit. With --notify it
                       returns once started and sends a notification at the end.
  smart-report [DRIVE] full `smartctl -x` output through pkexec (asks for your password)

OPTIONS
  --fresh       ignore the 10-minute cache of the SMART / kernel-log probes
  --notify      (smart-test) run the wait in the background, notify when done
  -h, --help    show this help

NEEDS
  udisks2 (SMART), smartctl (smart-report), nvidia-smi (NVIDIA GPU, optional)

RESUMO RÁPIDO
  stoa-hardware report
  stoa-hardware smart-test | smart-test extended nvme0 | smart-test --notify
  stoa-hardware smart-report
  stoa-hardware -h | --help
"""


# ══════════════════════════════════════════
#   Small helpers
# ══════════════════════════════════════════

def read(path, default=None):
    try:
        return Path(path).read_text().strip()
    except (OSError, UnicodeDecodeError):
        return default


def read_int(path, default=None):
    v = read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def run(cmd, timeout=15):
    """(returncode, stdout). -1 when the binary is missing or times out."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return -1, ""


def have(binary):
    return any((Path(d) / binary).exists()
               for d in os.environ.get("PATH", "").split(":") if d)


def celsius(milli):
    return None if milli is None else round(milli / 1000.0, 1)


# ══════════════════════════════════════════
#   udisks2 / SMART  (slow)
# ══════════════════════════════════════════

def _flat(props):
    return {k: v.get("data") for k, v in (props or {}).items()}


def udisks_drives():
    """{object path: {"drive": props, "nvme": props|None, "ata": props|None}}"""
    rc, out = run(["busctl", "--system", "--json=short", "call", UDISKS, U_ROOT,
                   "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"])
    if rc != 0 or not out.strip():
        return None
    try:
        objs = json.loads(out)["data"][0]
    except (ValueError, KeyError, IndexError):
        return None
    found = {}
    for path, ifs in objs.items():
        if I_DRIVE not in ifs:
            continue
        found[path] = {"drive": _flat(ifs[I_DRIVE]),
                       "nvme": _flat(ifs[I_NVME]) if I_NVME in ifs else None,
                       "ata": _flat(ifs[I_ATA]) if I_ATA in ifs else None}
    return found


def _call(path, iface, method, sig, *args, interactive=False, timeout=15):
    cmd = ["busctl", "--system", "--json=short"]
    if interactive:
        cmd.append("--allow-interactive-authorization=true")
    cmd += ["call", UDISKS, path, iface, method, sig, *args]
    return run(cmd, timeout)


def collect_smart(refresh=True):
    """{serial: smart dict}, or None when udisks2 cannot be reached."""
    drives = udisks_drives()
    if drives is None:
        return None
    if refresh:
        for path, d in drives.items():
            if d["nvme"] is not None:
                _call(path, I_NVME, "SmartUpdate", "a{sv}", "0")
            elif d["ata"] is not None:
                _call(path, I_ATA, "SmartUpdate", "a{sv}", "0")
        drives = udisks_drives() or drives
    smart = {}
    for path, d in drives.items():
        serial = (d["drive"].get("Serial") or "").strip()
        if not serial:
            continue
        if d["nvme"] is not None:
            n = d["nvme"]
            attrs = {}
            rc, out = _call(path, I_NVME, "SmartGetAttributes", "a{sv}", "0")
            if rc == 0:
                try:
                    attrs = _flat(json.loads(out)["data"][0])
                except (ValueError, KeyError, IndexError):
                    attrs = {}
            smart[serial] = {
                "kind": "nvme",
                "updated": n.get("SmartUpdated"),
                "criticalWarning": list(n.get("SmartCriticalWarning") or []),
                "powerOnHours": n.get("SmartPowerOnHours"),
                "tempC": (n["SmartTemperature"] - 273) if n.get("SmartTemperature") else None,
                "selftest": n.get("SmartSelftestStatus"),
                "percentUsed": attrs.get("percent_used"),
                "availSpare": attrs.get("avail_spare"),
                "spareThreshold": attrs.get("spare_thresh"),
                "mediaErrors": attrs.get("media_errors"),
                "errorLogEntries": attrs.get("num_err_log_entries"),
                "unsafeShutdowns": attrs.get("unsafe_shutdowns"),
                "powerCycles": attrs.get("power_cycles"),
                "writtenBytes": attrs.get("total_data_written"),
                "warnTempC": (attrs["wctemp"] - 273) if attrs.get("wctemp") else None,
                "critTempC": (attrs["cctemp"] - 273) if attrs.get("cctemp") else None,
                "warnTempMinutes": attrs.get("warning_temp_time"),
                "critTempMinutes": attrs.get("critical_temp_time"),
            }
        elif d["ata"] is not None:
            a = d["ata"]
            if not a.get("SmartSupported"):
                continue
            temp = a.get("SmartTemperature")
            smart[serial] = {
                "kind": "ata",
                "updated": a.get("SmartUpdated"),
                "failing": bool(a.get("SmartFailing")),
                "powerOnHours": int((a.get("SmartPowerOnSeconds") or 0) / 3600),
                "tempC": round(temp - 273.15) if temp else None,
                "badSectors": a.get("SmartNumBadSectors"),
                "attrsFailing": a.get("SmartNumAttributesFailing"),
                "selftest": a.get("SmartSelftestStatus"),
            }
    return smart


# ══════════════════════════════════════════
#   Kernel log  (slow)
# ══════════════════════════════════════════

# key, severity, area, description, pattern
JOURNAL_RULES = [
    ("io",      "fail", "storage", "disk I/O errors",
     r"Buffer I/O error|blk_update_request: (?:I/O|critical|timeout)"),
    ("nvme",    "fail", "storage", "NVMe controller errors",
     r"nvme\d+: .*(?:timeout|controller is down|reset controller|Removing after probe failure)"),
    ("fs",      "fail", "storage", "filesystem errors",
     r"EXT4-fs error|BTRFS (?:error|critical)|XFS \(.*(?:Corruption|metadata I/O error)|F2FS-fs.*error"),
    ("mce",     "fail", "cpu",     "machine-check / memory hardware errors",
     r"mce: \[Hardware Error\]|Machine check|EDAC .*(?:UE|CE|uncorrect)|\[Hardware Error\]"),
    ("pcie",    "warn", "system",  "PCIe bus errors",
     r"pcieport .*AER:|PCIe Bus Error"),
    ("gpu_lost", "fail", "gpu",    "GPU fell off the bus",
     r"fallen off the bus|NVRM: Xid.*\b79\b"),
    ("gpu_amd", "warn", "gpu",     "AMD GPU hangs/resets",
     r"amdgpu.*(?:ring \S+ timeout|GPU reset begin|GPU reset\(\d+\) failed|VRAM is lost)"),
    ("gpu_nv",  "warn", "gpu",     "NVIDIA Xid errors",
     r"NVRM: Xid"),
    ("display", "warn", "display", "display link errors",
     r"flip_done timed out|[Ll]ink training failed|\[drm\] \*ERROR\* .*(?:aux|dpcd|link)"),
    ("thermal", "warn", "cpu",     "thermal throttling",
     r"temperature above threshold|clock throttled|critical temperature reached"),
    ("oom",     "warn", "memory",  "out-of-memory kills",
     r"Out of memory: Killed|oom-kill:|invoked oom-killer"),
]
_COMPILED = [(k, re.compile(p)) for k, _, _, _, p in JOURNAL_RULES]


def classify(line):
    """Rule keys a kernel-log line belongs to."""
    return [key for key, rx in _COMPILED if rx.search(line)]


def collect_journal():
    """{"counts": {key: n}, "samples": {key: line}}, None if unreadable."""
    rc, probe = run(["journalctl", "-k", "-b", "-n1", "--no-pager", "-q", "-o", "cat"])
    if rc != 0 or not probe.strip():
        return None   # no access (or no log): silence is not "all clear"
    rc, out = run(["journalctl", "-k", "-b", "--no-pager", "-q", "-o", "cat"], timeout=30)
    if rc != 0:
        return None
    counts = {k: 0 for k, *_ in JOURNAL_RULES}
    samples = {}
    for line in out.splitlines():
        for key in classify(line):
            counts[key] += 1
            samples.setdefault(key, line.strip()[:160])
    # Xid 79 is reported as "lost", not twice.
    if counts["gpu_lost"]:
        counts["gpu_nv"] = max(0, counts["gpu_nv"] - counts["gpu_lost"])
    return {"counts": counts, "samples": samples}


def pci_names():
    names = {}
    rc, out = run(["lspci", "-D", "-mm"])
    if rc == 0:
        for line in out.splitlines():
            parts = re.findall(r'"([^"]*)"|(\S+)', line)
            parts = [a or b for a, b in parts]
            if len(parts) >= 4:
                vendor, device = parts[2], parts[3]
                short = ("AMD" if "AMD" in vendor else "NVIDIA" if "NVIDIA" in vendor
                         else "Intel" if "Intel" in vendor else vendor)
                inner = re.search(r"\[([^\]]+)\]\s*$", device)
                names[parts[0]] = f"{short} {inner.group(1) if inner else device}"
    return names


def slow(fresh=False):
    if not fresh:
        try:
            cached = json.loads(CACHE.read_text())
            if time.time() - cached.get("ts", 0) < SLOW_TTL:
                return cached
        except (OSError, ValueError):
            pass
    data = {"ts": time.time(), "smart": collect_smart(),
            "journal": collect_journal(), "pciNames": pci_names()}
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data))
        tmp.replace(CACHE)
    except OSError:
        pass
    return data


# ══════════════════════════════════════════
#   Live collection (sysfs / procfs)
# ══════════════════════════════════════════

def hwmon_by_name(*names):
    out = []
    for h in sorted((SYS / "class/hwmon").glob("hwmon*")):
        if read(h / "name") in names:
            out.append(h)
    return out


def collect_storage(sl):
    smart = sl.get("smart") or {}
    drives = []
    for n in sorted((SYS / "class/nvme").glob("nvme[0-9]*"),
                    key=lambda p: int(re.sub(r"\D", "", p.name) or 0)):
        serial = (read(n / "serial") or "").strip()
        temps = [read_int(t) for t in n.glob("hwmon*/temp1_input")]
        temps = [t for t in temps if t is not None]
        drives.append({
            "name": n.name, "kind": "nvme", "serial": serial,
            "model": " ".join((read(n / "model") or "NVMe").split()),
            "state": read(n / "state"),
            "tempC": celsius(temps[0]) if temps else None,
            "smart": smart.get(serial) if sl.get("smart") is not None else None,
            "smartAvailable": sl.get("smart") is not None,
        })
    for b in sorted((SYS / "block").glob("sd[a-z]")):
        serial = (read(b / "device/serial") or "").strip()
        s = smart.get(serial)
        drives.append({
            "name": b.name, "kind": "ata", "serial": serial,
            "model": " ".join((read(b / "device/model") or "SATA disk").split()),
            "state": "live", "tempC": s.get("tempC") if s else None,
            "smart": s, "smartAvailable": sl.get("smart") is not None,
        })

    fs = []
    for d in sorted((SYS / "fs/btrfs").glob("*-*-*-*-*")):
        errs = {}
        for stats in d.glob("devinfo/*/error_stats"):
            for line in (read(stats) or "").splitlines():
                k, _, v = line.partition(" ")
                if v.strip().isdigit():
                    errs[k] = errs.get(k, 0) + int(v)
        if errs:
            fs.append({"fs": "btrfs", "label": read(d / "label") or d.name[:8],
                       "errors": errs, "total": sum(errs.values())})
    return {"drives": drives, "filesystems": fs}


def collect_memory():
    mi = {}
    for line in (read(PROC / "meminfo") or "").splitlines():
        k, _, v = line.partition(":")
        parts = v.split()
        if parts and parts[0].isdigit():
            mi[k] = int(parts[0])
    total = mi.get("MemTotal", 0)
    swap_total = mi.get("SwapTotal", 0)
    swap_used = swap_total - mi.get("SwapFree", 0)
    psi = {}
    for line in (read(PROC / "pressure/memory") or "").splitlines():
        kind, _, rest = line.partition(" ")
        m = re.search(r"avg60=([\d.]+)", rest)
        if m:
            psi[kind] = float(m.group(1))
    ce = ue = 0
    edac = False
    for mc in (SYS / "devices/system/edac/mc").glob("mc[0-9]*"):
        edac = True
        ce += read_int(mc / "ce_count", 0)
        ue += read_int(mc / "ue_count", 0)
    dimm = []
    for h in hwmon_by_name("spd5118", "jc42"):
        t = read_int(h / "temp1_input")
        if t is not None:
            dimm.append(celsius(t))
    return {
        "totalGiB": round(total / 1048576, 1),
        "swapTotalGiB": round(swap_total / 1048576, 1),
        "swapUsedPct": round(100 * swap_used / swap_total, 1) if swap_total else 0.0,
        "pressureSome": psi.get("some", 0.0), "pressureFull": psi.get("full", 0.0),
        "edac": edac, "ecCorrected": ce, "ecUncorrected": ue,
        "dimmTempsC": dimm,
    }


def collect_cpu():
    model = ""
    for line in (read(PROC / "cpuinfo") or "").splitlines():
        if line.startswith("model name"):
            model = line.partition(":")[2].strip()
            break
    model = re.sub(r"\s+with .*$|\(R\)|\(TM\)|\s+CPU\b|\s+\d+-Core Processor", "", model).strip()
    present = (read(SYS / "devices/system/cpu/present") or "")
    online = (read(SYS / "devices/system/cpu/online") or "")

    def count(spec):
        n = 0
        for part in spec.split(","):
            if "-" in part:
                a, _, b = part.partition("-")
                if a.isdigit() and b.isdigit():
                    n += int(b) - int(a) + 1
            elif part.isdigit():
                n += 1
        return n

    temp = None
    for h in hwmon_by_name("k10temp", "zenpower", "coretemp"):
        best = None
        for t in h.glob("temp*_input"):
            label = read(str(t).replace("_input", "_label"), "")
            v = read_int(t)
            if v is None:
                continue
            if label in ("Tctl", "Tdie", "Package id 0"):
                best = v
                break
            best = v if best is None else max(best, v)
        if best is not None:
            temp = celsius(best)
            break
    throttle = 0
    for f in (SYS / "devices/system/cpu").glob("cpu[0-9]*/thermal_throttle/*_throttle_count"):
        throttle += read_int(f, 0)
    return {"model": model or "CPU", "threads": count(present), "online": count(online),
            "tempC": temp, "throttleEvents": throttle}


def collect_gpus(sl):
    names = sl.get("pciNames") or {}
    gpus = []
    for dev in sorted((SYS / "bus/pci/devices").glob("*")):
        cls = read(dev / "class", "")
        if not cls.startswith("0x03"):
            continue
        vendor = read(dev / "vendor", "")
        addr = dev.name
        g = {"addr": addr, "name": names.get(addr, addr),
             "runtime": read(dev / "power/runtime_status", "unknown"),
             "tempC": None, "busyPct": None, "vramUsedMiB": None, "vramTotalMiB": None,
             "thermalSlowdown": False, "state": "active"}
        if vendor == "0x10de":
            g["vendor"] = "nvidia"
            if g["runtime"] == "suspended":
                # nvidia-smi would wake the card just to read a temperature.
                g["state"] = "asleep"
            elif have("nvidia-smi"):
                _nvidia(g)
        elif vendor == "0x1002":
            g["vendor"] = "amd"
            temps = [read_int(t) for t in dev.glob("hwmon/hwmon*/temp1_input")]
            temps = [t for t in temps if t is not None]
            g["tempC"] = celsius(temps[0]) if temps else None
            g["busyPct"] = read_int(dev / "gpu_busy_percent")
            used, tot = read_int(dev / "mem_info_vram_used"), read_int(dev / "mem_info_vram_total")
            if used is not None and tot:
                g["vramUsedMiB"], g["vramTotalMiB"] = used // 1048576, tot // 1048576
        else:
            g["vendor"] = "intel" if vendor == "0x8086" else "other"
        gpus.append(g)
    return gpus


def _nvidia(g):
    for prefix in ("clocks_throttle_reasons", "clocks_event_reasons"):
        rc, out = run(["nvidia-smi", "--query-gpu=name,temperature.gpu,utilization.gpu,"
                       "memory.used,memory.total,"
                       f"{prefix}.hw_thermal_slowdown,{prefix}.sw_thermal_slowdown",
                       "--format=csv,noheader,nounits"], timeout=10)
        if rc == 0 and out.strip():
            f = [x.strip() for x in out.splitlines()[0].split(",")]
            if len(f) >= 7:
                def num(x):
                    try:
                        return float(x)
                    except ValueError:
                        return None
                g["name"] = f[0] or g["name"]
                g["tempC"] = num(f[1])
                g["busyPct"] = num(f[2])
                g["vramUsedMiB"], g["vramTotalMiB"] = num(f[3]), num(f[4])
                # hw_thermal_slowdown is the chip protecting itself. The
                # software flag is raised by mobile drivers at idle (0x20 in
                # the active mask at 38°C), so it only counts when it's hot.
                g["thermalSlowdown"] = f[5] == "Active" or \
                    (f[6] == "Active" and (g["tempC"] or 0) >= 80)
            return


def collect_display():
    conns = {}
    for c in sorted((SYS / "class/drm").glob("card[0-9]*-*")):
        name = c.name.split("-", 1)[1]
        status = read(c / "status", "unknown")
        enabled = read(c / "enabled", "disabled")
        if name.endswith(("Writeback-1",)) or "Writeback" in name:
            continue
        prev = conns.get(name)
        if prev and prev["status"] == "connected":
            continue
        mode = (read(c / "modes", "") or "").splitlines()
        conns[name] = {"name": name, "status": status, "enabled": enabled == "enabled",
                       "mode": mode[0] if mode else None,
                       "internal": name.startswith(("eDP", "LVDS", "DSI"))}
    bl = None
    for b in sorted((SYS / "class/backlight").glob("*")):
        cur, mx = read_int(b / "brightness"), read_int(b / "max_brightness")
        if cur is not None and mx:
            bl = {"name": b.name, "pct": round(100 * cur / mx)}
            break
    return {"connectors": list(conns.values()), "backlight": bl}


def collect_battery():
    for b in sorted((SYS / "class/power_supply").glob("BAT*")):
        if read(b / "type") != "Battery":
            continue
        full = read_int(b / "charge_full") or read_int(b / "energy_full")
        design = read_int(b / "charge_full_design") or read_int(b / "energy_full_design")
        ac = None
        for p in (SYS / "class/power_supply").glob("*"):
            if read(p / "type") == "Mains":
                ac = read(p / "online") == "1"
        cycles = read_int(b / "cycle_count")
        return {
            "name": b.name, "status": read(b / "status"),
            "capacityPct": read_int(b / "capacity"),
            "level": read(b / "capacity_level"),
            "healthPct": round(100 * full / design, 1) if full and design else None,
            "cycles": cycles if cycles else None,
            "acOnline": ac,
        }
    return None


def collect(fresh=False):
    sl = slow(fresh)
    return {
        "ts": int(time.time()),
        "smartAgeSec": int(time.time() - sl.get("ts", time.time())),
        "storage": collect_storage(sl),
        "memory": collect_memory(),
        "cpu": collect_cpu(),
        "gpus": collect_gpus(sl),
        "display": collect_display(),
        "battery": collect_battery(),
        "kernel": sl.get("journal"),
    }


# ══════════════════════════════════════════
#   Judgement
# ══════════════════════════════════════════

def evaluate(d):
    """Findings: [{"level": ok|info|warn|fail, "area": str, "msg": str}]."""
    out = []

    def add(level, area, msg):
        out.append({"level": level, "area": area, "msg": msg})

    # ── Storage ──
    for dr in d["storage"]["drives"]:
        label = f'{dr["model"]} ({dr["name"]})'
        s = dr.get("smart")
        if s is None:
            why = "udisks2 unavailable" if not dr.get("smartAvailable") else "no SMART data"
            add("info", "storage", f"{label}: SMART not read ({why})")
            continue
        bad = False
        temp = dr.get("tempC") if dr.get("tempC") is not None else s.get("tempC")
        if s["kind"] == "nvme":
            if s["criticalWarning"]:
                add("fail", "storage", f'{label}: SMART critical warning ({", ".join(s["criticalWarning"])})')
                bad = True
            spare, thr = s.get("availSpare"), s.get("spareThreshold")
            if spare is not None and thr is not None and spare <= thr:
                add("fail", "storage", f"{label}: spare capacity {spare}% at or below its {thr}% threshold")
                bad = True
            used = s.get("percentUsed")
            if used is not None and used >= 90:
                add("fail", "storage", f"{label}: {used}% of rated endurance used")
                bad = True
            elif used is not None and used >= 80:
                add("warn", "storage", f"{label}: {used}% of rated endurance used")
                bad = True
            if s.get("mediaErrors"):
                add("fail", "storage", f'{label}: {s["mediaErrors"]} media/data-integrity errors')
                bad = True
            # Lifetime counters that never reset: a minute or two over a long
            # life is noise, so only a sustained history is a warning.
            if s.get("critTempMinutes"):
                add("warn", "storage", f'{label}: {s["critTempMinutes"]} min spent above critical temperature')
                bad = True
            elif (s.get("warnTempMinutes") or 0) >= 30:
                add("warn", "storage", f'{label}: {s["warnTempMinutes"]} min spent above warning temperature')
                bad = True
            crit_t, warn_t = s.get("critTempC"), s.get("warnTempC")
            if temp is not None and crit_t and temp >= crit_t:
                add("fail", "storage", f"{label}: {temp:.0f}°C is at its critical limit ({crit_t}°C)")
                bad = True
            elif temp is not None and warn_t and temp >= warn_t:
                add("warn", "storage", f"{label}: {temp:.0f}°C is above its warning limit ({warn_t}°C)")
                bad = True
        else:
            if s.get("failing"):
                add("fail", "storage", f"{label}: SMART overall health FAILING")
                bad = True
            if s.get("badSectors"):
                add("warn", "storage", f'{label}: {s["badSectors"]} bad sectors')
                bad = True
            if s.get("attrsFailing"):
                add("warn", "storage", f'{label}: {s["attrsFailing"]} SMART attributes failing')
                bad = True
            if temp is not None and temp >= 60:
                add("warn", "storage", f"{label}: {temp:.0f}°C")
                bad = True
        st = s.get("selftest")
        if st and st not in ("success", "inprogress", "never"):
            add("warn", "storage", f"{label}: last SMART self-test result: {st}")
            bad = True
        if not bad:
            bits = []
            if temp is not None:
                bits.append(f"{temp:.0f}°C")
            if s.get("percentUsed") is not None:
                bits.append(f'{s["percentUsed"]}% worn')
            if s.get("availSpare") is not None:
                bits.append(f'spare {s["availSpare"]}%')
            if s["kind"] == "nvme":
                bits.append(f'{s.get("mediaErrors") or 0} media errors')
                if s.get("writtenBytes"):
                    bits.append(f'{s["writtenBytes"] / 1e12:.1f} TB written')
                if s.get("unsafeShutdowns"):
                    bits.append(f'{s["unsafeShutdowns"]} unsafe shutdowns')
                if s.get("warnTempMinutes"):
                    bits.append(f'{s["warnTempMinutes"]} min over warn temp (lifetime)')
            if s.get("powerOnHours") is not None:
                bits.append(f'{s["powerOnHours"]} h on')
            add("ok", "storage", f'{label}: {", ".join(bits)}')

    for fs in d["storage"]["filesystems"]:
        if fs["total"]:
            e = fs["errors"]
            add("fail", "storage",
                f'Btrfs {fs["label"]}: {fs["total"]} device errors '
                f'(read {e.get("read_errs", 0)}, write {e.get("write_errs", 0)}, '
                f'flush {e.get("flush_errs", 0)}, corruption {e.get("corruption_errs", 0)}, '
                f'generation {e.get("generation_errs", 0)}) — see: btrfs device stats')
        else:
            add("ok", "storage", f'Btrfs {fs["label"]}: no device errors')

    # ── Memory ──
    m = d["memory"]
    bad = False
    if m["ecUncorrected"]:
        add("fail", "memory", f'{m["ecUncorrected"]} uncorrected memory (ECC) errors')
        bad = True
    if m["ecCorrected"]:
        add("warn", "memory", f'{m["ecCorrected"]} corrected memory (ECC) errors')
        bad = True
    if m["swapUsedPct"] >= 80:
        add("warn", "memory", f'Swap {m["swapUsedPct"]:.0f}% full')
        bad = True
    if m["pressureFull"] >= 10:
        add("warn", "memory", f'Memory pressure: tasks stalled {m["pressureFull"]:.0f}% of the last minute')
        bad = True
    for t in m["dimmTempsC"]:
        if t is not None and t >= 95:
            add("fail", "memory", f"DIMM at {t:.0f}°C")
            bad = True
        elif t is not None and t >= 85:
            add("warn", "memory", f"DIMM at {t:.0f}°C")
            bad = True
    if not bad:
        bits = [f'{m["totalGiB"]:g} GiB', f'swap {m["swapUsedPct"]:.0f}%']
        if m["dimmTempsC"]:
            bits.append("DIMM " + "/".join(f"{t:.0f}°C" for t in m["dimmTempsC"]))
        bits.append("ECC counters clean" if m["edac"] else "no ECC reporting")
        add("ok", "memory", "Memory: " + ", ".join(bits))

    # ── CPU ──
    c = d["cpu"]
    bad = False
    if c["tempC"] is not None and c["tempC"] >= 100:
        add("fail", "cpu", f'{c["model"]} at {c["tempC"]:.0f}°C')
        bad = True
    elif c["tempC"] is not None and c["tempC"] >= 90:
        add("warn", "cpu", f'{c["model"]} at {c["tempC"]:.0f}°C')
        bad = True
    if c["online"] < c["threads"]:
        add("warn", "cpu", f'{c["threads"] - c["online"]} of {c["threads"]} CPU threads are offline')
        bad = True
    if c["throttleEvents"]:
        add("warn", "cpu", f'{c["throttleEvents"]} thermal-throttle events counted')
        bad = True
    if not bad:
        t = f', {c["tempC"]:.0f}°C' if c["tempC"] is not None else ""
        add("ok", "cpu", f'{c["model"]}: {c["online"]} threads online{t}')

    # ── GPUs ──
    for g in d["gpus"]:
        label = f'{g["name"]}'
        t = g.get("tempC")
        warn_t, fail_t = (85, 95) if g.get("vendor") == "nvidia" else (90, 100)
        if t is not None and t >= fail_t:
            add("fail", "gpu", f"{label} at {t:.0f}°C")
        elif t is not None and t >= warn_t:
            add("warn", "gpu", f"{label} at {t:.0f}°C")
        elif g.get("thermalSlowdown"):
            add("warn", "gpu", f"{label} is thermally throttled")
        elif g.get("state") == "asleep":
            add("ok", "gpu", f"{label}: powered down (runtime PM), not woken to probe")
        else:
            bits = []
            if t is not None:
                bits.append(f"{t:.0f}°C")
            if g.get("busyPct") is not None:
                bits.append(f'{g["busyPct"]:.0f}% busy')
            if g.get("vramTotalMiB"):
                bits.append(f'VRAM {g["vramUsedMiB"]:.0f}/{g["vramTotalMiB"]:.0f} MiB')
            add("ok", "gpu", f'{label}: ' + (", ".join(bits) or "present"))

    # ── Display ──
    disp = d["display"]
    internal = [x for x in disp["connectors"] if x["internal"]]
    for x in internal:
        if x["status"] != "connected":
            add("fail", "display", f'Internal panel {x["name"]} is not detected ({x["status"]})')
        elif not x["enabled"]:
            add("warn", "display", f'Internal panel {x["name"]} is connected but disabled')
        else:
            bl = disp.get("backlight")
            extra = f', backlight {bl["pct"]}%' if bl else ""
            add("ok", "display", f'Internal panel {x["name"]}: {x["mode"] or "enabled"}{extra}')
    ext = [x for x in disp["connectors"] if not x["internal"] and x["status"] == "connected"]
    for x in ext:
        if x["enabled"]:
            add("ok", "display", f'External display {x["name"]}: {x["mode"] or "enabled"}')
        else:
            add("info", "display", f'External display {x["name"]} is connected but not enabled')

    # ── Battery ──
    b = d["battery"]
    if b:
        bad = False
        h = b.get("healthPct")
        if h is not None and h < 60:
            add("fail", "battery", f"Battery wear: only {h:.0f}% of design capacity left")
            bad = True
        elif h is not None and h < 80:
            add("warn", "battery", f"Battery wear: {h:.0f}% of design capacity left")
            bad = True
        if b.get("level") in ("Critical",) and b.get("status") != "Charging":
            add("warn", "battery", f'Battery critically low ({b.get("capacityPct")}%)')
            bad = True
        if not bad:
            bits = [f'{b.get("capacityPct")}% {str(b.get("status") or "").lower()}'.strip()]
            if h is not None:
                bits.append(f"health {h:.0f}%")
            if b.get("cycles"):
                bits.append(f'{b["cycles"]} cycles')
            add("ok", "battery", "Battery: " + ", ".join(bits))

    # ── Kernel log ──
    k = d.get("kernel")
    if k is None:
        add("info", "kernel", "Kernel log not readable from this session (hardware error scan skipped)")
    else:
        any_hit = False
        for key, sev, area, desc, _ in JOURNAL_RULES:
            n = k["counts"].get(key, 0)
            if n:
                any_hit = True
                sample = k.get("samples", {}).get(key, "")
                add(sev, area, f"Kernel log: {desc} ({n}× this boot) — e.g. {sample}")
        if not any_hit:
            add("ok", "kernel", "Kernel log: no hardware errors this boot")
    return out


def tally(findings):
    return (sum(f["level"] == "fail" for f in findings),
            sum(f["level"] == "warn" for f in findings))


# ══════════════════════════════════════════
#   Commands
# ══════════════════════════════════════════

def build(fresh=False):
    d = collect(fresh)
    f = evaluate(d)
    issues, warnings = tally(f)
    d["findings"] = f
    d["issues"], d["warnings"] = issues, warnings
    return d


def cmd_report(d):
    icon = {"ok": "✓", "info": "·", "warn": "!", "fail": "✗"}
    area = None
    for f in sorted(d["findings"], key=lambda x: (x["area"], ["fail", "warn", "info", "ok"].index(x["level"]))):
        if f["area"] != area:
            area = f["area"]
            print(f"\n{area.upper()}")
        print(f'  {icon[f["level"]]} {f["msg"]}')
    print(f'\n{d["issues"]} issue(s), {d["warnings"]} warning(s)')


def _select(drives, target):
    """Drives (udisks objects) matching nvme0 / serial / model fragment."""
    if not target:
        return list(drives.items())
    t = target.lower()
    out = []
    for path, d in drives.items():
        dr = d["drive"]
        hay = " ".join(str(dr.get(k, "")) for k in ("Serial", "Model", "Id")).lower()
        sys_name = ""
        for n in (SYS / "class/nvme").glob("nvme[0-9]*"):
            if (read(n / "serial") or "").strip() == dr.get("Serial"):
                sys_name = n.name
        if t in hay or t == sys_name or t == sys_name + "n1":
            out.append((path, d))
    return out


def cmd_smart_test(kind, target, notify=False):
    if kind not in ("short", "extended"):
        sys.exit(f"stoa-hardware: unknown self-test kind '{kind}' (short or extended)")
    drives = udisks_drives()
    if not drives:
        sys.exit("stoa-hardware: udisks2 is not reachable — is udisks2.service running?")
    chosen = [(p, d) for p, d in _select(drives, target) if d["nvme"] or d["ata"]]
    if not chosen:
        sys.exit("stoa-hardware: no SMART-capable drive matches" + (f" '{target}'" if target else ""))
    started = []
    rc_all = 0
    for path, d in chosen:
        iface = I_NVME if d["nvme"] else I_ATA
        model = d["drive"].get("Model") or path.rsplit("/", 1)[-1]
        rc, out = _call(path, iface, "SmartSelftestStart", "sa{sv}", kind, "0",
                        interactive=True, timeout=120)
        if rc == 0:
            print(f"Started {kind} self-test on {model}")
            started.append((path, iface, model))
        else:
            print(f"Could not start the self-test on {model} (not authorised, or the drive is busy)")
            rc_all = 1
    if not started:
        return rc_all
    if kind == "extended":
        print("Extended tests take a while; the result shows in `stoa-hardware report --fresh`.")
        return rc_all
    if notify:
        # Hand the wait to a detached child so the caller (the bar panel)
        # is not held for minutes; the result arrives as a notification.
        if os.fork() > 0:
            print("The result will arrive as a notification when the test finishes.")
            return rc_all
        os.setsid()
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(devnull, fd)
        _follow(started, lambda m: run(["notify-send", "-a", "Stoa Hardware", "SMART self-test", m]))
        os._exit(0)
    return _follow(started, print) or rc_all


def _follow(started, say, timeout=900):
    """Poll until every started self-test ends; say() each result."""
    rc_all = 0
    pending = list(started)
    deadline = time.time() + timeout
    while pending and time.time() < deadline:
        time.sleep(5)
        still = []
        for path, iface, model in pending:
            _call(path, iface, "SmartUpdate", "a{sv}", "0")
            rc, out = run(["busctl", "--system", "--json=short", "get-property", UDISKS,
                           path, iface, "SmartSelftestStatus"])
            try:
                status = json.loads(out)["data"]
            except (ValueError, KeyError):
                status = "unknown"
            if status == "inprogress":
                still.append((path, iface, model))
            else:
                say(f"{model}: self-test finished — {status}")
                if status != "success":
                    rc_all = 1
        pending = still
    for _, _, model in pending:
        say(f"{model}: still running after {timeout // 60} min — check `stoa-hardware report --fresh` later")
    try:
        CACHE.unlink()
    except OSError:
        pass
    return rc_all


def smart_report_cmd(devs):
    """One pkexec for every drive. A prompt per drive would mean N password
    boxes, and each dismissed one counts as a failed login to pam_faillock —
    three of them and sudo, polkit and the login screen all stop working."""
    script = 'for d in "$@"; do echo; echo "══════ $d ══════"; smartctl -x "$d"; done'
    return ["pkexec", "/bin/sh", "-c", script, "sh", *devs]


def cmd_smart_report(target):
    if not have("smartctl"):
        sys.exit("stoa-hardware: smartctl is not installed (pacman -S smartmontools)")
    devs = []
    for n in sorted((SYS / "class/nvme").glob("nvme[0-9]*")):
        dev = f"/dev/{n.name}n1"
        if not target or target.lower() in (n.name, dev.rsplit("/", 1)[-1]) \
                or target.lower() in (read(n / "model") or "").lower() \
                or target == (read(n / "serial") or "").strip():
            devs.append(dev)
    for b in sorted((SYS / "block").glob("sd[a-z]")):
        if not target or target.lower() in (b.name, (read(b / "device/model") or "").lower()):
            devs.append(f"/dev/{b.name}")
    if not devs:
        sys.exit("stoa-hardware: no drive matches" + (f" '{target}'" if target else ""))
    p = subprocess.run(smart_report_cmd(devs))
    # smartctl's exit status is a bit mask (most bits are findings, not
    # failures); only pkexec's own codes mean the report never ran.
    return 1 if p.returncode in (126, 127) else 0


def main(argv):
    args = [a for a in argv if a not in ("--fresh", "--notify")]
    fresh = "--fresh" in argv
    notify = "--notify" in argv
    cmd = args[0] if args else "json"
    if cmd in ("-h", "--help", "help"):
        print(HELP, end="")
        return 0
    if cmd == "smart-test":
        rest = args[1:]
        kind = rest[0] if rest and rest[0] in ("short", "extended") else "short"
        target = next((a for a in rest if a not in ("short", "extended")), None)
        return cmd_smart_test(kind, target, notify)
    if cmd == "smart-report":
        return cmd_smart_report(args[1] if len(args) > 1 else None)
    if cmd not in ("json", "summary", "report", "doctor"):
        print(f"stoa-hardware: unknown command '{cmd}' (try --help)", file=sys.stderr)
        return 2
    d = build(fresh or cmd == "doctor")
    if cmd == "json":
        print(json.dumps(d))
    elif cmd == "summary":
        d["findings"] = sorted((f for f in d["findings"] if f["level"] in ("warn", "fail")),
                               key=lambda f: f["level"] != "fail")
        d.pop("kernel", None)
        print(json.dumps(d))
    elif cmd == "report":
        cmd_report(d)
    else:
        for f in d["findings"]:
            print(f'{f["level"]}\t{f["msg"]}')
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
