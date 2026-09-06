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

  R3  the shipped Noctalia palette is still the Stoic one. Applying a
      custom palette writes StoaCustom.json beside it precisely so that
      Stoa.json keeps meaning Stoa; if a future change points the
      rewrite at the shipped file instead, the palette named Stoa
      silently becomes Dracula and there is no way back to the original.

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
SETTINGS = ROOT / "scripts" / "stoa-settings.sh"
SHIPPED_PALETTE = ROOT / "config" / "noctalia" / "palettes" / "Stoa.json"

# How many of the Stoic role colours the shipped palette must still carry.
# It uses nine of the eleven — the two it leaves out have no Material role
# in Noctalia — so six is a floor with room to re-map a couple of roles.
MIN_STOIC_ROLES = 6

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


def presets() -> dict[str, list[str]]:
    """The palette table from stoa-settings.sh, name -> role colours."""
    body = SETTINGS.read_text(errors="replace")
    out = {}
    for line in body.split("\n"):
        if line.count("|") != 11:
            continue
        *colours, name = line.split("|")
        # the table's own header comment has the same shape, so require
        # every field to actually be a colour
        if not all(re.fullmatch(r"#[0-9a-fA-F]{6}", c) for c in colours):
            continue
        out[name.strip()] = [c.lower() for c in colours]
    return out


def check_shipped_palette() -> list[str]:
    if not SHIPPED_PALETTE.is_file():
        return [f"{SHIPPED_PALETTE.name} is missing — it is what \"Stoa\" means"]
    table = presets()
    stoic = next((v for k, v in table.items() if k.startswith("Stoic")), None)
    if not stoic:
        return ["could not read the Stoic row of _color_presets"]

    text = SHIPPED_PALETTE.read_text(errors="replace").lower()
    kept = [c for c in stoic if c in text]
    rel = SHIPPED_PALETTE.relative_to(ROOT)
    problems = []
    if len(kept) < MIN_STOIC_ROLES:
        problems.append(
            f"{rel}: only {len(kept)} Stoic colours left — the shipped palette has "
            "drifted away from the Stoic default it is supposed to be"
        )
    for name, colours in table.items():
        if name.startswith("Stoic"):
            continue
        borrowed = sorted({c for c in colours if c in text and c not in stoic})
        if borrowed:
            problems.append(
                f"{rel}: carries {name} colours ({', '.join(borrowed)}) — a custom "
                "palette must be written to StoaCustom.json, never over the shipped one"
            )
    return problems


def main() -> int:
    problems = check_hook_targets() + check_conf_options() + check_shipped_palette()
    for problem in problems:
        print(f"config-integrity: {problem}")
    if problems:
        print(f"\n{len(problems)} integrity problem(s) found.", file=sys.stderr)
        return 1
    print("config-integrity: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
