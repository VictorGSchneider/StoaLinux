#!/usr/bin/env python3
"""Static check for yad menu dispatch bugs in the stoa-* scripts.

Every stoa menu is built the same way: a list of literal labels is handed to
_yad_select / _yad_list, the selected label comes back as a string, and the
script decides what to do with `[[ "$choice" == *Something* ]]` guards and a
`case` of `*substring*` patterns.

Because those matches are unanchored substrings, a label can be swallowed by a
pattern meant for a *different* label — "  Backup Configs" matches the
`*"Back"*` guard that exists to close the menu, so the entry is unreachable and
its case branch is dead code. Two rules catch that class:

  R1  at most one label of a menu may match the guard that returns/continues
      /breaks out of it (otherwise picking a real entry silently exits)
  R2  when a label matches several case patterns, the first one must be the
      longest — the most specific pattern has to win, not merely the topmost

Pattern-versus-pattern shadowing (`*"5 minute"*` before `*"15 minute"*`) is
already covered by shellcheck SC2221/SC2222 in CI; this checker is about
label-versus-pattern, which shellcheck cannot see.
"""

from __future__ import annotations

import fnmatch
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCH_DIRS = ("scripts", "setup", "shell", "theme", "config", "dotfiles")

ITEM_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
ASSIGN_RE = re.compile(
    r"(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)=\$\(\s*(?:printf|echo)?.*?_yad_(?:select|list)\b"
)
SUBST_RE = re.compile(r"\$\{[^}]*\}|\$\([^)]*\)|\$[A-Za-z_][A-Za-z0-9_]*")
SEPARATOR = "─"


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
    return out


def unquote(pattern: str) -> str:
    """Drop the quoting bash itself removes before matching."""
    return pattern.replace('"', "").replace("'", "")


def literal_len(pattern: str) -> int:
    """Length of the literal text in a glob, i.e. its specificity."""
    return len(unquote(pattern).replace("*", "").replace("?", ""))


def split_case_pattern(line: str) -> str | None:
    """Return the pattern of a `case` branch, honouring quotes and nesting."""
    depth, quote, out = 0, None, []
    for ch in line.lstrip():
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "(":
            depth += 1
            out.append(ch)
        elif ch == ")":
            if depth == 0:
                return "".join(out).strip()
            depth -= 1
            out.append(ch)
        else:
            out.append(ch)
    return None


def parse_menus(path: Path):
    """Yield (line, items, guard, patterns) for every menu in `path`."""
    lines = path.read_text(errors="replace").split("\n")
    i = 0
    while i < len(lines):
        assign = ASSIGN_RE.search(lines[i])
        if not assign:
            i += 1
            continue
        var = assign.group(1)
        end, call = i, lines[i]
        while call.rstrip().endswith("\\") and end + 1 < len(lines):
            end += 1
            call += "\n" + lines[end]

        items = [m.group(1) for m in ITEM_RE.finditer(call)]
        if "_yad_select" in call and items:
            items = items[1:]  # first argument is the window title
        items = [
            SUBST_RE.sub("X", it)
            for it in items
            if it.strip() and set(it.strip()) != {SEPARATOR}
        ]

        guard = patterns = None
        guard_re = re.compile(
            r'\$\{?%s\}?"?\s*==\s*(\*[^\]&|]*?\*?)\s*\]\]' % re.escape(var)
        )
        case_re = re.compile(r'\s*case\s+"?\$\{?%s\}?"?\s+in' % re.escape(var))
        k = end + 1
        while k < min(end + 30, len(lines)):
            if guard is None and re.search(r"\b(return|continue|break)\b", lines[k]):
                found = guard_re.search(lines[k])
                if found:
                    guard = (found.group(1).strip(), k + 1)
            if case_re.match(lines[k]):
                patterns, k, in_branch = [], k + 1, False
                while k < len(lines):
                    line = lines[k]
                    if not in_branch and re.match(r"\s*esac\b", line):
                        break
                    if in_branch:
                        in_branch = ";;" not in line
                    elif line.strip() and not line.lstrip().startswith("#"):
                        pattern = split_case_pattern(line)
                        if pattern and not pattern.startswith(";"):
                            patterns.append((pattern, k + 1))
                            in_branch = ";;" not in line
                    k += 1
                break
            k += 1

        if items and (guard or patterns):
            yield i + 1, items, guard, patterns or []
        i = end + 1


def matches(item: str, pattern: str) -> bool:
    if "$" in pattern or "`" in pattern:
        return False  # runtime value, nothing to decide statically
    return any(
        fnmatch.fnmatchcase(item, unquote(alt.strip()))
        for alt in pattern.split("|")
        if alt.strip() and alt.strip() != "*"
    )


def check(path: Path) -> list[str]:
    rel = path.relative_to(ROOT)
    problems = []
    for line, items, guard, patterns in parse_menus(path):
        if guard:
            swallowed = [it for it in items if matches(it, guard[0])]
            if len(swallowed) > 1:
                problems.append(
                    f"{rel}:{guard[1]}: guard {guard[0]} matches {len(swallowed)} "
                    f"labels of the menu at line {line}, so picking "
                    + " or ".join(repr(s.strip()) for s in swallowed if s.strip() != "Back")
                    + " leaves the menu instead of acting: "
                    + ", ".join(repr(s) for s in swallowed)
                )
        for item in items:
            hits = [(p, ln) for p, ln in patterns if matches(item, p)]
            if len(hits) < 2:
                continue
            best = max(hits, key=lambda h: literal_len(h[0]))
            if best is not hits[0]:
                problems.append(
                    f"{rel}:{hits[0][1]}: pattern {hits[0][0]} claims {item!r} "
                    f"before the more specific {best[0]} on line {best[1]}"
                )
    return problems


def main() -> int:
    problems = [p for f in shell_files() for p in check(f)]
    for problem in problems:
        print(f"menu-dispatch: {problem}")
    if problems:
        print(f"\n{len(problems)} menu dispatch problem(s) found.", file=sys.stderr)
        return 1
    print("menu-dispatch: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
