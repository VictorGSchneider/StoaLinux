#!/usr/bin/env python3
"""Static invariants from the November 2026 audit.

Every rule here is a defect that shipped, passed CI, and broke something a
user touches. None of them is a syntax error and none crashes loudly, which
is why bash -n, shellcheck and luac all read green over them:

  H1  a path a script builds from its own location must exist. The refactor
      that grouped scripts into folders moved stoa-settings.sh one level
      down and left `…/lib/stoa-yad.sh` pointing at scripts/desktop/lib.
      `[ -r ] && source` skips a missing file without a word, so the panel
      lost stoa_yad_list and Super+S has opened nothing since.

  H2  a script install.sh links into ~/.local/bin must not locate the repo
      through a bare "$0": through the symlink that is ~/.local/bin, and
      `$(dirname "$0")/../..` is $HOME. stoa-gpu-setup changes drivers,
      modprobe.d and the initramfs first and only then fails to find
      shell/stoa-env.sh.

  H3  config/hypr/hyprland.lua carries no machine-local state. Three
      things got in through the ~/.config/hypr symlink and a `stoa-sync`
      commit: the hyprlock autostart commented out by the greetd toggle
      (autologin then boots to an unlocked desktop), a GPU block naming
      /dev/dri/nvidia-card (a udev symlink only stoa-gpu-setup creates), and
      require("noctalia") for a module the repo does not ship — Hyprland's
      own --verify-config rejects the file over that one.

  H4  shell/stoa-env.sh keeps its GPU variables commented out, as its own
      header says. stoa-gpu-setup rewrites them in the tracked file with
      file-wide seds, so the NVIDIA and Intel sections were committed
      saying radeonsi and every clone exports the author's VA-API driver.

  H5  .gitignore must not swallow documentation. Bare `README.md` and
      `LICENSE` lines ignored scripts/README.md, written for the folder
      refactor and never committed.

  H6  every Super+<key> in README.md is bound. check_config_integrity's R3
      reads scripts/, config/, theme/… but not the README at the repo root,
      where the keybind table still offers Super+Shift+V.

  H7  nothing root executes may be a symlink into the checkout, nor a
      root unit whose ExecStart is a file in it. The pacman hooks and the
      programs they run are linked from /etc and /usr/local/bin straight to
      files the user owns: whoever can write those files is root at the
      next pacman transaction, with no password asked. The polkit rule and
      the greetd guard are already copied for the same reason.

  H8  setup/archinstall/user_configuration.json installs a subset of what
      post-install.sh installs, and includes the shell. It still listed
      waybar, swaybg and cliphist, and never noctalia — so the live-ISO path
      produced a Hyprland session with no bar, launcher or lock screen.

  H9  a dialog-driven script calls no bare `sudo`. Started from a keybind
      it has no terminal, so sudo cannot ask: the action does nothing and
      PAM logs a failed authentication that pam_faillock counts — three of
      them lock the account for ten minutes. Use pkexec, `sudo -n`, or a
      terminal (kitty -e, _run_in_term, _maintain_run_term).

  H10 a script reached from a compositor bind does not call its siblings
      by bare name. niri and Hyprland start children with the session PATH,
      which has no ~/.local/bin (that is why every bind names the full
      path). `stoa-firewall allow …` inside stoa-settings is then "command
      not found", hidden behind 2>/dev/null.

scripts/vendor/** and the DFM fork are upstream code and out of scope.
"""

from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.sh"
HYPRLAND = ROOT / "config" / "hypr" / "hyprland.lua"
ENV_FILE = ROOT / "shell" / "stoa-env.sh"
GITIGNORE = ROOT / ".gitignore"
README = ROOT / "README.md"
MAINTAIN = ROOT / "scripts" / "system" / "stoa-maintain.sh"
POST_INSTALL = ROOT / "setup" / "post-install.sh"
ARCHINSTALL = ROOT / "setup" / "archinstall" / "user_configuration.json"

SHELL_DIRS = ("scripts", "setup", "shell", "theme")
SKIP_PARTS = ("vendor", "stoa-dfm")


# ── shared helpers ───────────────────────────────────────────────────

def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def shell_files() -> list[Path]:
    out = []
    for d in SHELL_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            if not p.is_file() or any(s in p.parts for s in SKIP_PARTS):
                continue
            if p.suffix == ".sh":
                out.append(p)
            elif not p.suffix:
                head = p.open("rb").read(40)
                if head.startswith(b"#!") and (b"bash" in head or b"/sh" in head):
                    out.append(p)
    if INSTALL.is_file():
        out.append(INSTALL)
    return out


def linked_bins() -> dict[Path, str]:
    """Repo file -> command name, for everything install.sh links into ~/.local/bin."""
    out = {}
    text = INSTALL.read_text(errors="replace")
    for src, name in re.findall(
            r'_link\s+"\$\{STOA_DIR\}/([^"]+)"\s+(?:\\\n\s*)?"\$\{HOME\}/\.local/bin/([^"]+)"', text):
        out[ROOT / src] = name
    return out


def code_lines(path: Path):
    """(number, line with quoted strings blanked) for lines that are code.

    Skips comments, heredoc bodies and the inside of a single-quoted string
    that spans lines (the `kitty -e bash -c '…'` blocks). Quoted segments are
    replaced by "" so that a word inside a message is not mistaken for a
    command, while the command that receives the message stays visible.
    """
    heredoc = None
    in_squote = False
    for number, raw in enumerate(path.read_text(errors="replace").split("\n"), 1):
        if heredoc is not None:
            if raw.strip() == heredoc:
                heredoc = None
            continue
        if in_squote:
            if raw.count("'") % 2 == 1:
                in_squote = False
            continue
        line = raw
        if line.lstrip().startswith("#"):
            continue
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
        if m:
            heredoc = m.group(1)
        stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
        stripped = re.sub(r"'[^']*'", "''", stripped)
        if stripped.count("'") % 2 == 1:
            in_squote = True
            stripped = stripped[:stripped.rindex("'")]
        stripped = re.sub(r"\s#.*$", "", stripped)
        yield number, stripped, raw


# ── H1: script-relative paths exist ──────────────────────────────────

_SRC = r'\$\{?(?P<src>BASH_SOURCE\[0\]|0)\}?'
_SELF = (r'(?P<dn>(?:\$\(dirname "){1,4})\$\(readlink -f "' + _SRC + r'"\)(?:"\)){1,4}')
_REL = r'(?P<rel>(?:/[A-Za-z0-9_.-]+)*)'
DIRECT_RE = re.compile(_SELF + _REL)
CD_RE = re.compile(r'\$\(cd "' + _SELF + r'(?P<up>(?:/\.\.)*)" && pwd\)' + _REL)
ASSIGN_RE = re.compile(r'(?:^|[\s;])(?:local\s+)?(?P<var>[A-Za-z_][A-Za-z0-9_]*)=["\']?$')


def _base_dir(path: Path, src: str, dirnames: int) -> Path:
    base = path.parent
    # `$0` in a sourced module is the entry script, not the module: for
    # scripts/packages/stoa-store/system.sh that is scripts/packages/.
    if src == "0" and (path.parent.parent / (path.parent.name + ".sh")).is_file():
        base = path.parent.parent
    for _ in range(dirnames - 1):
        base = base.parent
    return base


def check_relative_paths() -> list[str]:
    problems = []
    for f in shell_files():
        text = f.read_text(errors="replace")
        lines = text.split("\n")
        bases: dict[str, tuple[Path, int]] = {}
        for number, line in enumerate(lines, 1):
            if line.lstrip().startswith("#"):
                continue
            spans = []
            for m in CD_RE.finditer(line):
                base = _base_dir(f, m.group("src"), m.group("dn").count("dirname"))
                target = (base / m.group("up").lstrip("/")).resolve() if m.group("up") else base
                spans.append((m, target, m.group("rel")))
            taken = [(m.start(), m.end()) for m, _, _ in spans]
            for m in DIRECT_RE.finditer(line):
                if any(s <= m.start() < e for s, e in taken):
                    continue
                base = _base_dir(f, m.group("src"), m.group("dn").count("dirname"))
                spans.append((m, base, m.group("rel")))
            for m, base, suffix in spans:
                target = (base / suffix.lstrip("/")) if suffix else base
                if not target.exists():
                    shown = os.path.relpath(os.path.normpath(target), ROOT)
                    problems.append(
                        f"{rel(f)}:{number}: builds …{suffix} from its own location, which is "
                        f"{shown} — no such path (stale after a move?)")
                    continue
                a = ASSIGN_RE.search(line[:m.start()])
                if a:
                    bases[a.group("var")] = (target, number)
        for var, (base, where) in bases.items():
            use = re.compile(r'\$\{?' + re.escape(var) + r'\}?((?:/[A-Za-z0-9_.-]+)+)')
            for number, line in enumerate(lines, 1):
                if line.lstrip().startswith("#"):
                    continue
                for m in use.finditer(line):
                    target = base / m.group(1).lstrip("/")
                    if not target.exists():
                        shown = os.path.relpath(os.path.normpath(base), ROOT)
                        problems.append(
                            f"{rel(f)}:{number}: ${var}{m.group(1)} — line {where} sets ${var} "
                            f"to {shown}/, and there is no such path under it")
    return sorted(set(problems))


# ── H2: no bare $0 in symlinked entry points ─────────────────────────

def check_dollar_zero() -> list[str]:
    problems = []
    for f, name in sorted(linked_bins().items()):
        if not f.is_file() or f.suffix == ".py":
            continue
        for number, line in enumerate(f.read_text(errors="replace").split("\n"), 1):
            if line.lstrip().startswith("#"):
                continue
            if re.search(r'dirname "\$\{?0\}?"', line):
                problems.append(
                    f"{rel(f)}:{number}: locates the repo through \"$0\"; run as the "
                    f"installed `{name}` that is ~/.local/bin — resolve the symlink first "
                    "(readlink -f \"${BASH_SOURCE[0]}\")")
    return problems


# ── H3: hyprland.lua carries no machine-local state ──────────────────

def check_hyprland_state() -> list[str]:
    if not HYPRLAND.is_file():
        return []
    problems = []
    name = rel(HYPRLAND)
    lines = HYPRLAND.read_text(errors="replace").split("\n")
    for number, line in enumerate(lines, 1):
        if "disabled by stoa-greetd" in line:
            problems.append(
                f"{name}:{number}: the hyprlock autostart is committed in its greetd-disabled "
                "state — enable-stoa-greeter.sh (autologin) relies on it as the password prompt")
        if "stoa-gpu-setup: env (auto-managed) >>>" in line:
            problems.append(
                f"{name}:{number}: a stoa-gpu-setup env block is committed — it is one "
                "machine's GPU layout (AQ_DRM_DEVICES and friends), not a default")
        if re.match(r'\s*hl\.env\("(AQ|WLR)_DRM_DEVICES"', line):
            problems.append(
                f"{name}:{number}: pins DRM devices for every clone: {line.strip()}")
        code = line.split("--", 1)[0]
        for module in re.findall(r'\brequire\(\s*"([^"]+)"\s*\)', code):
            if "pcall" in code:
                continue
            candidates = [HYPRLAND.parent / (module.replace(".", "/") + ".lua"),
                          HYPRLAND.parent / module.replace(".", "/") / "init.lua"]
            if not any(c.is_file() for c in candidates):
                problems.append(
                    f"{name}:{number}: require(\"{module}\") — config/hypr/{module}.lua is not "
                    "shipped, so Hyprland stops with \"module not found\" (guard it with pcall "
                    "or ship the module)")
    return problems


# ── H4: stoa-env.sh GPU block stays a template ───────────────────────

GPU_VARS = ("LIBVA_DRIVER_NAME", "VDPAU_DRIVER", "__GLX_VENDOR_LIBRARY_NAME",
            "GBM_BACKEND", "NVD_BACKEND", "WLR_NO_HARDWARE_CURSORS",
            "__GL_GSYNC_ALLOWED", "__GL_VRR_ALLOWED")


def check_env_template() -> list[str]:
    if not ENV_FILE.is_file():
        return []
    problems = []
    name = rel(ENV_FILE)
    for number, line in enumerate(ENV_FILE.read_text(errors="replace").split("\n"), 1):
        m = re.match(r"\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=(\S*)", line)
        if m and m.group(1) in GPU_VARS:
            problems.append(
                f"{name}:{number}: {m.group(1)}={m.group(2)} is active in the tracked file — "
                "the header promises these stay commented until stoa-gpu-setup runs, and "
                "this value is one machine's GPU")
    return problems


# ── H5: .gitignore does not swallow docs ─────────────────────────────

def check_gitignore() -> list[str]:
    if not GITIGNORE.is_file():
        return []
    problems = []
    for number, line in enumerate(GITIGNORE.read_text(errors="replace").split("\n"), 1):
        name = line.strip()
        if name not in {"README.md", "LICENSE", "README", "*.md"}:
            continue
        why = ("scripts/README.md was written for the folder refactor and never committed "
               "because of it" if "README" in name or name == "*.md"
               else "a fork's own licence file can never be added")
        problems.append(
            f".gitignore:{number}: `{name}` ignores that name in every folder — {why}")
    return problems


# ── H6: README keybinds ──────────────────────────────────────────────

def _integrity_module():
    spec = importlib.util.spec_from_file_location(
        "check_config_integrity", Path(__file__).with_name("check_config_integrity.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_readme_keybinds() -> list[str]:
    if not README.is_file():
        return []
    cci = _integrity_module()
    hypr, niri = cci.bound_shortcuts(), cci.niri_bound_shortcuts()
    bound = hypr | niri
    pattern = re.compile(
        r"\b(?:Super|Win)\s*\+\s*(?:(?:Shift|Ctrl|Alt)\s*\+\s*)*"
        r"(?:[A-Za-z0-9/]+(?:\s+(?:Click|Drag))?)", re.IGNORECASE)
    problems = []
    for number, line in enumerate(README.read_text(errors="replace").split("\n"), 1):
        for raw in pattern.findall(line):
            combo = cci._norm_combo(raw)
            head, _, tail = combo.rpartition("+")
            if tail in {"SHIFT", "CTRL", "ALT", "HJKL", "H/J/K/L"} or combo in bound:
                continue
            if len(tail) == 3 and tail[1] in "-–" and all(
                    f"{head}+{c}" in bound for c in (tail[0], tail[2])):
                continue
            keys = tail.split("/")
            if len(keys) > 1 and all(len(k) == 1 for k in keys) and all(
                    f"{head}+{k}" in bound for k in keys):
                continue
            problems.append(
                f"README.md:{number}: documents {raw!r}, which neither hyprland.lua nor "
                "niri's config.kdl binds")
    return problems


# ── H7: root never runs a file from the checkout ─────────────────────

ROOT_RUN_DIRS = ("/etc/pacman.d/hooks", "/usr/local/bin", "/usr/local/sbin",
                 "/usr/local/lib", "/etc/systemd/system", "/etc/udev", "/etc/polkit-1")


def check_root_runs_repo() -> list[str]:
    problems = []
    text = INSTALL.read_text(errors="replace")
    variables = dict(re.findall(r'^([A-Z_]+)="(/[^"$]*)"', text, re.MULTILINE))
    pattern = re.compile(
        r'_sudo_link\s+"\$\{STOA_DIR\}/(?P<src>[^"]+)"\s+(?:\\\n\s*)?"?(?P<dst>[^"\s]+)"?')
    for m in pattern.finditer(text):
        dst = m.group("dst")
        for var, value in variables.items():
            dst = dst.replace("${" + var + "}", value).replace("$" + var, value)
        if dst.startswith(ROOT_RUN_DIRS):
            number = text.count("\n", 0, m.start()) + 1
            problems.append(
                f"install.sh:{number}: {dst} becomes a symlink to {m.group('src')} — root "
                "runs it on every pacman transaction and the user can rewrite it; install a "
                "root-owned copy, as the polkit rule and the greetd guard already are")
    if MAINTAIN.is_file():
        for number, line in enumerate(MAINTAIN.read_text(errors="replace").split("\n"), 1):
            if re.match(r"\s*ExecStart=.*\$script_path.*--unattended", line):
                problems.append(
                    f"{rel(MAINTAIN)}:{number}: the root systemd unit runs $script_path, a "
                    "file in the user's checkout, at every boot")
    return problems


# ── H8: archinstall list ⊆ post-install ──────────────────────────────

def check_archinstall_packages() -> list[str]:
    if not (ARCHINSTALL.is_file() and POST_INSTALL.is_file()):
        return []
    listed = json.loads(ARCHINSTALL.read_text())["packages"]
    post = POST_INSTALL.read_text(errors="replace")
    known = set()
    # Indented too: the compositor and lock packages are assigned inside
    # `case "$WM_CHOICE"` arms.
    for value in re.findall(r'\b[A-Z_]+(?:_PKGS(?:_QS)?|_APPS)="([^"]*)"', post):
        known.update(value.split())
    known.update(re.findall(r"_install_aur\s+(\S+)", post))
    shell = set()
    for value in re.findall(r'^SHELL_PKGS_QS="([^"]*)"', post, re.MULTILINE):
        shell.update(value.split())
    name = rel(ARCHINSTALL)
    problems = [
        f"{name}: installs {p}, which post-install.sh does not — a package the desktop "
        "stopped using, still pulled in by the live-ISO path"
        for p in listed if p not in known]
    problems += [
        f"{name}: does not install {p} (post-install.sh's shell engine) — the session "
        "arch-install.sh announces as complete has no bar, launcher or lock screen"
        for p in sorted(shell) if p not in listed]
    return problems


# ── H9: no bare sudo in dialog-driven scripts ────────────────────────

TERMINAL_WRAPPERS = re.compile(
    r"kitty\b.*\s-e\b|\$TERM_CMD|\$\{TERM_CMD\}|\$term\b|_run_in_term|_in_terminal|"
    r"_maintain_run_term|\bpkexec\b")


def gui_scripts() -> list[Path]:
    out = []
    for f in shell_files():
        if f.parts[len(ROOT.parts)] != "scripts":
            continue
        text = f.read_text(errors="replace")
        # A yad menu and nothing that hands the whole script to a terminal.
        if re.search(r"\b_yad_(select|confirm|input|list|pipe)\b", text):
            out.append(f)
    return out


def check_gui_sudo() -> list[str]:
    problems = []
    for f in gui_scripts():
        # Functions that are only ever entered from a terminal wrapper.
        text = f.read_text(errors="replace")
        terminal_only = set(re.findall(r"_in_terminal\s+\S.*\s([a-z][a-z-]*-run)\b", text))
        skip_until = None
        for number, line, raw in code_lines(f):
            if skip_until is not None:
                if raw.startswith("}"):
                    skip_until = None
                continue
            m = re.match(r"\s*(_[a-z_]+)\(\)\s*\{", raw)
            if m and any(m.group(1) == "_" + t.replace("-", "_") for t in terminal_only):
                skip_until = m.group(1)
                continue
            if not re.search(r"(^|[^A-Za-z0-9_-])sudo(\s|$)", line):
                continue
            if re.search(r"sudo\s+-n\b", line) or TERMINAL_WRAPPERS.search(line):
                continue
            problems.append(
                f"{rel(f)}:{number}: bare sudo in a dialog-driven script — no terminal to "
                f"ask on, so it fails and pam_faillock counts it: {raw.strip()[:90]}")
    return problems


# ── H10: no bare sibling calls from bind-launched scripts ────────────

SIBLING_RE = re.compile(
    r"(?:^|[;&|()]|\bthen\b|\bdo\b|\belse\b|\$\(|<\(|\bexec\b|\bnohup\b|\s-e)\s*"
    r"(?:sudo\s+)?(stoa-[a-z][a-z-]*)\b")


def check_bare_siblings() -> list[str]:
    names = set(linked_bins().values())
    problems = []
    for f in gui_scripts():
        text = f.read_text(errors="replace")
        if re.search(r"\bPATH=[^\n]*\.local/bin", text):
            continue
        for number, line, raw in code_lines(f):
            for m in SIBLING_RE.finditer(line):
                cmd = m.group(1)
                if cmd not in names:
                    continue
                problems.append(
                    f"{rel(f)}:{number}: calls `{cmd}` by bare name — from a compositor "
                    "bind ~/.local/bin is not on PATH, so this is \"command not found\": "
                    f"{raw.strip()[:80]}")
    return problems


RULES = (
    ("H1", check_relative_paths),
    ("H2", check_dollar_zero),
    ("H3", check_hyprland_state),
    ("H4", check_env_template),
    ("H5", check_gitignore),
    ("H6", check_readme_keybinds),
    ("H7", check_root_runs_repo),
    ("H8", check_archinstall_packages),
    ("H9", check_gui_sudo),
    ("H10", check_bare_siblings),
)


def main() -> int:
    only = set(sys.argv[1:])
    total = 0
    for rule, fn in RULES:
        if only and rule not in only:
            continue
        for problem in fn():
            print(f"repo-hygiene {rule}: {problem}")
            total += 1
    if total:
        print(f"\n{total} hygiene problem(s) found.", file=sys.stderr)
        return 1
    print("repo-hygiene: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
