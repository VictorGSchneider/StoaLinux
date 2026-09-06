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

  R3  every Super+<key> shortcut written down anywhere in the tree is a
      shortcut hyprland.lua actually binds. Docs drift the moment a bind
      moves: the settings panel was advertised as Super+I in eight places
      long after the bind became Super+S, and the cheatsheet in the bar
      still offered a Super+M that was never bound at all.

  R4  the shipped Noctalia palette is still the Stoic one. Applying a
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
HYPRLAND = ROOT / "config" / "hypr" / "hyprland.lua"

# Spellings people use in prose for keys hyprland.lua names differently.
KEY_ALIASES = {
    "ESC": "ESCAPE",
    "SLASH": "/",
    "LEFTDRAG": "MOUSE:272",
    "LEFTCLICK": "MOUSE:272",
    "RIGHTDRAG": "MOUSE:273",
    "RIGHTCLICK": "MOUSE:273",
}
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


def _norm_combo(text: str) -> str:
    """Normalise one shortcut to MOD+MOD+KEY, uppercase, no spaces."""
    parts = [p.strip().upper() for p in text.split("+") if p.strip()]
    parts = [{"WIN": "SUPER"}.get(p, p) for p in parts]
    parts[-1] = KEY_ALIASES.get(parts[-1].replace(" ", ""), parts[-1])
    return "+".join(parts)


def bound_shortcuts() -> set[str]:
    """Every shortcut hyprland.lua binds, normalised."""
    text = HYPRLAND.read_text(errors="replace")
    out = set()
    for combo in re.findall(r'hl\.bind\(mod \.\. " \+ ([^"]+)"', text):
        out.add(_norm_combo("SUPER+" + combo))
    for combo in re.findall(r'hl\.bind\("([^"]+)"', text):
        out.add(_norm_combo(combo))
    # the workspace loop binds mod .. " + " .. key for keys 1..9 and 0
    if 'hl.bind(mod .. " + " .. key' in text:
        for key in "1234567890":
            out.add(f"SUPER+{key}")
            out.add(f"SUPER+SHIFT+{key}")
    return out


def documented_shortcuts() -> list[tuple[Path, int, str, str]]:
    """Every Super+<key> written in the tree, as (file, line, raw, normalised)."""
    # A trailing modifier alone ("Super+Shift+…") is prose, not a shortcut.
    pattern = re.compile(
        r"\b(?:Super|Win)\s*\+\s*"
        r"(?:(?:Shift|Ctrl|Alt)\s*\+\s*)*"
        r"(?:[A-Za-z0-9/]+(?:\s+(?:Click|Drag))?)",
        re.IGNORECASE,
    )
    found = []
    for f in reader_files():
        if f.suffix == ".lua" or f.name == HYPRLAND.name:
            continue
        # config/noctalia/{plugins,settings.json,colors.json} are the v4
        # leftovers config.toml calls inert: nothing installs them and v5
        # never reads them, so their shortcut lists describe a shell that
        # no longer exists. Skipped rather than fixed — the fix is to
        # delete them, which is not this check's call to make.
        if "noctalia" in f.parts and (
            "plugins" in f.parts or f.name in {"settings.json", "colors.json"}
        ):
            continue
        try:
            lines = f.read_text(errors="replace").split("\n")
        except OSError:
            continue
        for number, line in enumerate(lines, 1):
            for raw in pattern.findall(line):
                tail = raw.split("+")[-1].strip().upper()
                if tail in {"SHIFT", "CTRL", "ALT"}:
                    continue
                # shorthands the docs use for a run of binds
                if tail in {"HJKL", "H/J/K/L"}:
                    continue
                found.append((f, number, raw, _norm_combo(raw)))
    return found


def check_keybind_docs() -> list[str]:
    if not HYPRLAND.is_file():
        return []
    bound = bound_shortcuts()
    if len(bound) < 20:
        return [f"could not read the keybinds from {HYPRLAND.name}"]
    problems = []
    for f, number, raw, combo in documented_shortcuts():
        if combo in bound:
            continue
        # "Super+1-0" style ranges: accept if every endpoint is bound
        head, _, tail = combo.rpartition("+")
        if len(tail) == 3 and tail[1] in "-–" and all(
            f"{head}+{c}" in bound for c in (tail[0], tail[2])
        ):
            continue
        problems.append(
            f"{f.relative_to(ROOT)}:{number}: documents {raw!r}, which "
            f"{HYPRLAND.name} does not bind"
        )
    return problems


def main() -> int:
    problems = (check_hook_targets() + check_conf_options()
                + check_keybind_docs() + check_shipped_palette())
    for problem in problems:
        print(f"config-integrity: {problem}")
    if problems:
        print(f"\n{len(problems)} integrity problem(s) found.", file=sys.stderr)
        return 1
    print("config-integrity: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
