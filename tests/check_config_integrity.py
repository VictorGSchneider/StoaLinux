#!/usr/bin/env python3
"""Static check that what the repo ships and what it runs stay in step.

Two invariants. Neither breaks loudly — nothing crashes, the desktop just
quietly stops doing what the config says it does, which is exactly why
they went unnoticed:

  R1  every pacman hook's `Exec =` names a path install.sh actually
      creates. A hook whose program is missing makes pacman print a
      failed-hook error on every single transaction, forever.

  R2  every option documented in stoa.conf is read by something. A knob
      nobody reads is a promise the desktop does not keep — stoa.conf
      offered a bar engine long after the alternative was removed from
      stoa-bar.sh.

Commented-out options in stoa.conf count: they are documentation of a
supported setting, and a user who uncomments one expects it to work.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.sh"
CONF = ROOT / "stoa.conf"
HOOK_DIR = ROOT / "theme" / "pacman-hooks"

# Where a setting could plausibly be read. stoa.conf itself is excluded —
# it declares the options, it does not consume them.
READERS = ("scripts", "setup", "shell", "config", "theme", "dotfiles")


def reader_files() -> list[Path]:
    out = []
    for d in READERS:
        base = ROOT / d
        if base.is_dir():
            out += [p for p in base.rglob("*") if p.is_file() and "vendor" not in p.parts]
    if INSTALL.is_file():
        out.append(INSTALL)
    return out


def check_hook_targets() -> list[str]:
    if not HOOK_DIR.is_dir():
        return []
    install = INSTALL.read_text(errors="replace")
    problems = []
    for hook in sorted(HOOK_DIR.glob("*.hook")):
        text = hook.read_text(errors="replace")
        for target in re.findall(r"^\s*Exec\s*=\s*(\S+)", text, re.MULTILINE):
            if target not in install:
                problems.append(
                    f"{hook.relative_to(ROOT)}: Exec = {target}, which install.sh never "
                    "creates — pacman reports a failed hook on every transaction"
                )
    return problems


def check_conf_options() -> list[str]:
    if not CONF.is_file():
        return []
    options = []
    for line in CONF.read_text(errors="replace").split("\n"):
        m = re.match(r"^#?\s*([A-Z][A-Z0-9_]*)=", line)
        if m:
            options.append(m.group(1))
    if not options:
        return [f"{CONF.name}: no options found — has the format changed?"]

    blobs = []
    for f in reader_files():
        try:
            blobs.append(f.read_text(errors="replace"))
        except OSError:
            continue
    haystack = "\n".join(blobs)

    problems = []
    for option in sorted(set(options)):
        if not re.search(rf"\b{re.escape(option)}\b", haystack):
            problems.append(
                f"{CONF.name}: {option} is documented but nothing reads it — either "
                "wire it up or drop it, so the file cannot promise what it won't do"
            )
    return problems


def main() -> int:
    problems = check_hook_targets() + check_conf_options()
    for problem in problems:
        print(f"config-integrity: {problem}")
    if problems:
        print(f"\n{len(problems)} integrity problem(s) found.", file=sys.stderr)
        return 1
    print("config-integrity: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
