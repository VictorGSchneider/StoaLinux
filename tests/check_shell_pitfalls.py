#!/usr/bin/env python3
"""Static check for bash operator-precedence traps in the stoa-* scripts.

Bash gives `&&` and `||` the same precedence and evaluates them left to
right, so `A && B || C && D` is `(((A && B) || C) && D)`, not the
if/elif/else it reads like. When A and B both succeed, the `|| C` is
skipped, the chain is still true, and **D runs anyway** — the "else"
branch fires on the success path.

That is how every colour editor in stoa-settings.sh accepted a valid hex
and then reported "Invalid hex color" in the same breath. The shape is
rare enough in this tree to ban outright: write an if/elif when there are
three branches.

Two-part chains (`A && B` or `A || B`) and the idiomatic
`A && B || C` are left alone — only a `&&` that reaches *past* a `||` to
another `&&` on the same line is reported.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH_DIRS = ("scripts", "setup", "shell", "theme", "config", "dotfiles")

# `&& <something> || <something> &&` with no further && or || inside the
# middle terms, so only the genuine three-branch chain matches.
CHAIN_RE = re.compile(r"&&[^&|]+\|\|[^&|]+&&")


def shell_files() -> list[Path]:
    out = []
    for d in SEARCH_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            if not p.is_file() or "vendor" in p.parts:
                continue
            if p.suffix == ".sh":
                out.append(p)
            elif not p.suffix:
                head = p.open("rb").read(40)
                if head.startswith(b"#!") and (b"bash" in head or b"/sh" in head):
                    out.append(p)
    for extra in ("install.sh",):
        if (ROOT / extra).is_file():
            out.append(ROOT / extra)
    return out


def check(path: Path) -> list[str]:
    problems = []
    for number, line in enumerate(path.read_text(errors="replace").split("\n"), 1):
        if line.lstrip().startswith("#"):
            continue
        if CHAIN_RE.search(line):
            problems.append(
                f"{path.relative_to(ROOT)}:{number}: `A && B || C && D` runs D on the "
                f"success path too — use if/elif: {line.strip()}"
            )
    return problems


def main() -> int:
    problems = [p for f in shell_files() for p in check(f)]
    for problem in problems:
        print(f"shell-pitfall: {problem}")
    if problems:
        print(f"\n{len(problems)} precedence trap(s) found.", file=sys.stderr)
        return 1
    print("shell-pitfalls: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
