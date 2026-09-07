#!/usr/bin/env python3
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — History Keeper                                ║
# ║  "Only what serves, stays."                                  ║
# ║                                                              ║
# ║  Reads the shell history files, tells you what is in them,   ║
# ║  and prunes what stopped earning its place.                  ║
# ╚══════════════════════════════════════════════════════════════╝
"""Analyse and prune shell history files.

USAGE
  stoa-history                    # what is in your history (read-only)
  stoa-history clean              # what a prune would remove (dry run)
  stoa-history clean --apply      # actually prune, after a backup
  stoa-history suggest            # aliases worth having, from what you type
  stoa-history restore            # put the last backup back

WHAT IT PRUNES  (each class can be switched off: --no-secrets, --no-junk,
                 --no-noise, --days 0, --no-dedupe)
  secrets    lines carrying a token, key or password — history is
             world-readable to anything running as you, and a rotated
             credential still lives in this file forever
  junk       /tmp scratch, ./a.out, foo/bar/asdf placeholders
  noise      ls, cd .., clear, exit — a keystroke to retype, never
             a keystroke to search for
  old        entries older than --days (365 by default). Only entries
             that carry a timestamp: an undated line is never aged out
  duplicate  the same command typed before; the most recent copy stays,
             so Ctrl-R keeps finding it where you last used it

WHAT IT NEVER DOES
  Reorder. History is chronological and stays that way — "organising"
  it into groups would break every Ctrl-R and !! you have.

  Touch a file without a backup first: every write is preceded by a copy
  under ~/.local/state/stoa/history-backups (the last 10 are kept), and
  nothing is written at all until you pass --apply.

FILES
  bash (~/.bash_history) and zsh (~/.zsh_history) are handled natively,
  timestamps and multi-line commands included. --include-repl adds the
  line-based REPL histories (python, node, mysql, psql, sqlite, redis);
  those only get the secret, age and duplicate passes, since `ls` is not
  noise inside a python prompt.

  fish and atuin keep their history in their own database format. They
  are reported when present and never modified — `history merge` and
  `atuin search` are their own tools.

  Kitty has no command history of its own: its scrollback is this same
  file, so cleaning here is cleaning there.

KEEP LIST
  ~/.config/stoa/history-keep — one regex per line, `#` comments. Any
  entry matching one is exempt from every pass, duplicates included.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import time
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

HOME = Path.home()
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "stoa"
BACKUP_DIR = STATE_DIR / "history-backups"
KEEP_FILE = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "stoa/history-keep"
KEEP_BACKUPS = 10

# ── Palette (Stoa) ──
if sys.stdout.isatty():
    B = "\033[38;2;196;154;92m"   # bronze
    O = "\033[38;2;138;154;108m"  # olive
    T = "\033[38;2;179;107;90m"   # terracotta
    S = "\033[38;2;110;106;98m"   # stone
    F = "\033[38;2;212;207;196m"  # foreground
    R = "\033[0m"
else:
    B = O = T = S = F = R = ""

# ── Where history lives ──
# kind: "bash" | "zsh" | "repl" — it decides which passes apply, not just
# which parser runs. See KIND_PASSES below.
SHELL_FILES = [
    ("bash", HOME / ".bash_history"),
    ("zsh", HOME / ".zsh_history"),
    ("zsh", HOME / ".histfile"),
]
REPL_FILES = [
    ("repl", HOME / ".python_history"),
    ("repl", HOME / ".node_repl_history"),
    ("repl", HOME / ".mysql_history"),
    ("repl", HOME / ".psql_history"),
    ("repl", HOME / ".sqlite_history"),
    ("repl", HOME / ".rediscli_history"),
]
# Reported, never touched: their format is a database, not a list of lines.
FOREIGN_FILES = [
    ("fish", HOME / ".local/share/fish/fish_history", "use `history` inside fish"),
    ("atuin", HOME / ".local/share/atuin/history.db", "use `atuin search` / `atuin prune`"),
    ("nushell", HOME / ".config/nushell/history.txt", "nushell keeps its own history"),
]

# ── Noise: commands cheaper to retype than to find ──
NOISE_EXACT = {
    "ls", "l", "ll", "la", "lla", "lsa", "ls -l", "ls -a", "ls -la", "ls -al",
    "ls -lah", "ls -lh", "ll -a", "dir", "cd", "cd ..", "cd ../..", "cd ../../..",
    "cd -", "cd ~", "cd /", "..", "...", "pwd", "clear", "cls", "c", "reset",
    "exit", "logout", "q", ":q", ":wq", "quit", "history", "fg", "bg", "jobs",
    "y", "n", "yes", "no", "ok", "k", "sudo", "sudo !!", "!!", "whoami", "date",
    "z", "bash", "zsh", "sh", "top",
}
NOISE_RE = [
    re.compile(r"^\s*$"),                       # blank
    re.compile(r"^\s*#"),                       # a comment typed at the prompt
    re.compile(r"^.{1,2}$"),                    # one or two characters
    re.compile(r"^\s*(ls|ll|la)\s+-{0,2}[a-zA-Z]*\s*$"),
]
# --aggressive: the first word alone is enough to call it noise.
AGGRESSIVE_HEADS = {
    "ls", "ll", "la", "cd", "cat", "bat", "echo", "man", "which", "whereis",
    "type", "whoami", "date", "cal", "uptime", "df", "free", "clear",
}

# ── Junk: scratch work that outlived its scratch directory ──
PLACEHOLDERS = {
    "foo", "bar", "baz", "qux", "asdf", "asdfasdf", "asd", "qwe", "qwerty",
    "test", "teste", "test1", "test2", "test123", "tmp", "aaa", "xxx", "zzz",
    "lorem", "blah",
}
JUNK_RE = [
    re.compile(r"(^|\s)/(var/)?tmp/"),          # anything under /tmp
    re.compile(r"^\s*cd\s+/(var/)?tmp\b"),
    re.compile(r"^\s*\./a\.out\b"),
    re.compile(r"^\s*(python3?|node|bash|sh)\s+\S*(test|tmp|scratch)\d*\.\w+\s*$"),
    re.compile(r"^\s*rm\s+(-\S+\s+)*\S*(test|tmp|scratch)\d*\S*\s*$"),
]

# ── Secrets: the class worth cleaning even if you clean nothing else ──
SECRET_RE = [
    re.compile(r"(?i)\b(pass|passwd|password|secret|token|api[_-]?key|"
               r"access[_-]?key|auth[_-]?token|client[_-]?secret)\s*=\s*\S"),
    re.compile(r"(?i)--(password|token|api-key|secret)[=\s]\S"),
    re.compile(r"(?i)\bmysql\b.*\s-p\S"),
    re.compile(r"(?i)\bcurl\b.*-H\s*['\"]?authorization:", re.I),
    re.compile(r"\bghp_[A-Za-z0-9]{16,}|\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\bAIza[0-9A-Za-z_\-]{30,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\becho\s+\S+\s*\|\s*sudo\s+-S\b"),
    re.compile(r"(?i)\bgpg\b.*--passphrase\s+\S"),
]

# Words that start a line without naming a program — --strip-unknown must
# not read them as a typo.
SHELL_WORDS = {
    "cd", "export", "alias", "unalias", "source", ".", "exit", "set", "unset",
    "umask", "ulimit", "jobs", "fg", "bg", "kill", "wait", "read", "eval",
    "exec", "trap", "shopt", "setopt", "unsetopt", "history", "type", "hash",
    "times", "let", "local", "declare", "typeset", "pushd", "popd", "dirs",
    "bind", "builtin", "command", "compgen", "complete", "disown", "enable",
    "getopts", "printf", "echo", "pwd", "return", "shift", "suspend", "test",
    "[", "[[", "unlimit", "zle", "autoload", "emulate", "noglob", "true",
    "false", "for", "while", "until", "if", "then", "else", "elif", "fi",
    "do", "done", "case", "esac", "function", "select", "time", "coproc",
}

# Which passes a file kind is subject to. `ls` is noise in a shell and a
# variable name in a python REPL, so the shell-shaped passes stay out of
# REPL files rather than being tuned for them.
KIND_PASSES = {
    "bash": ("secret", "junk", "noise", "unknown", "old"),
    "zsh": ("secret", "junk", "noise", "unknown", "old"),
    "repl": ("secret", "old"),
}

REASON_ORDER = ["secret", "junk", "noise", "unknown", "old", "duplicate", "trimmed"]
REASON_LABEL = {
    "secret": "secret",
    "junk": "junk",
    "noise": "noise",
    "unknown": "unknown",
    "old": "old",
    "duplicate": "duplicate",
    "trimmed": "over cap",
}


@dataclass
class Entry:
    """One history entry.

    `raw` is the exact block of bytes-as-text this entry occupies in the
    file — timestamp line, continuation lines and all. Keeping an entry
    means writing its raw back untouched, so a rewrite can only ever
    remove entries, never reformat the survivors.
    """

    text: str
    ts: int | None
    raw: str
    reason: str | None = None


@dataclass
class HistoryFile:
    kind: str
    path: Path
    entries: list[Entry] = field(default_factory=list)
    size: int = 0


# ── Parsing ──────────────────────────────────────────────────────────

def raw_bytes(text: str) -> bytes:
    return text.encode("utf-8", errors="surrogateescape")


def printable(text: str) -> str:
    """Make a history line safe to print.

    zsh metafies bytes >= 0x80 and no shell promises UTF-8, so entries can
    carry bytes that decode to surrogates — printing one of those raises
    UnicodeEncodeError and takes the whole report down with it. The file
    keeps its bytes; only the report substitutes them.
    """
    return raw_bytes(text).decode("utf-8", errors="replace")


def read_text(path: Path) -> str:
    """Read a history file without ever failing on its bytes.

    zsh metafies bytes >= 0x80 and neither shell promises UTF-8, so
    surrogateescape carries the undecodable bytes through unchanged;
    writing back with the same codec reproduces them exactly.
    """
    return path.read_bytes().decode("utf-8", errors="surrogateescape")


def write_text(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".stoa-tmp")
    data = raw_bytes(text)
    try:
        mode = path.stat().st_mode & 0o777
    except OSError:
        mode = 0o600
    with open(tmp, "wb") as fh:
        fh.write(data)
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)


TS_LINE = re.compile(r"^#(\d{9,11})\s*$")
ZSH_LINE = re.compile(r"^: (\d{1,11}):(\d+);(.*)$", re.S)


def _ends_open(text: str) -> bool:
    """True when the line ends in an unescaped backslash (zsh continuation)."""
    n = len(text) - len(text.rstrip("\\"))
    return n % 2 == 1


def parse_bash(content: str) -> list[Entry]:
    """One entry per line, except where HISTTIMEFORMAT wrote `#<epoch>`
    markers: there an entry runs from one marker to the next, which is
    also how a multi-line command survives the round trip."""
    lines = content.splitlines(keepends=True)
    entries: list[Entry] = []
    ts: int | None = None
    raw: list[str] = []
    body: list[str] = []

    def flush() -> None:
        nonlocal ts, raw, body
        if raw:
            text = "".join(body).rstrip("\n")
            entries.append(Entry(text=text, ts=ts, raw="".join(raw)))
        ts, raw, body = None, [], []

    for line in lines:
        m = TS_LINE.match(line.rstrip("\n"))
        if m:
            flush()
            ts = int(m.group(1))
            raw = [line]
            continue
        if ts is None:
            # No open timestamped block: the line stands on its own.
            flush()
            raw = [line]
            body = [line]
            flush()
        else:
            raw.append(line)
            body.append(line)
    flush()
    return [e for e in entries if e.text.strip() or e.ts is not None]


def parse_zsh(content: str) -> list[Entry]:
    """Extended format (`: <epoch>:<elapsed>;<cmd>`) and plain lines, with
    the trailing-backslash continuation zsh uses for multi-line commands."""
    lines = content.splitlines(keepends=True)
    entries: list[Entry] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        raw = [line]
        stripped = line.rstrip("\n")
        m = ZSH_LINE.match(stripped)
        if m:
            ts: int | None = int(m.group(1))
            text = m.group(3)
        else:
            ts = None
            text = stripped
        while _ends_open(text) and i + 1 < len(lines):
            i += 1
            raw.append(lines[i])
            text = text[:-1] + "\n" + lines[i].rstrip("\n")
        entries.append(Entry(text=text, ts=ts, raw="".join(raw)))
        i += 1
    return [e for e in entries if e.text.strip()]


def parse_plain(content: str) -> list[Entry]:
    return [
        Entry(text=line.rstrip("\n"), ts=None, raw=line)
        for line in content.splitlines(keepends=True)
        if line.strip()
    ]


def load(kind: str, path: Path) -> HistoryFile:
    content = read_text(path)
    if kind == "zsh":
        entries = parse_zsh(content)
    elif kind == "bash":
        entries = parse_bash(content)
    else:
        entries = parse_plain(content)
    return HistoryFile(kind=kind, path=path, entries=entries,
                       size=path.stat().st_size)


# ── Classification ───────────────────────────────────────────────────

def load_keep_patterns() -> list[re.Pattern]:
    if not KEEP_FILE.is_file():
        return []
    out = []
    for number, line in enumerate(KEEP_FILE.read_text(errors="replace").splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            out.append(re.compile(line))
        except re.error as exc:
            warn(f"{KEEP_FILE}:{number}: not a valid regex ({exc}) — ignored")
    return out


def head_word(text: str) -> str:
    """The program a line runs, past sudo, env assignments and `time`."""
    for token in text.strip().split():
        if "=" in token.split("/")[0] and not token.startswith(("-", "/")):
            continue  # FOO=bar prefix
        if token in ("sudo", "doas", "time", "nohup", "command", "env", "\\"):
            continue
        return token
    return ""


def known_command(word: str, extra: set[str]) -> bool:
    if not word or word in SHELL_WORDS or word in extra:
        return True
    if "/" in word or not re.fullmatch(r"[A-Za-z0-9._+-]+", word):
        # A path, a pipeline, a subshell: whether ./configure exists depends
        # on the directory you were in when you ran it, which this file does
        # not record. Only bare words are judged.
        return True
    return shutil.which(word) is not None


def rc_names() -> set[str]:
    """Aliases and functions defined in the user's rc files.

    `command -v` cannot see them from here — a non-interactive python is
    not the shell that defines them — so --strip-unknown reads them out
    of the rc files instead. Without this, every alias you own looks like
    a typo.
    """
    names: set[str] = set()
    rcs = [HOME / ".bashrc", HOME / ".zshrc", HOME / ".bash_aliases",
           HOME / ".config/stoa/aliases.sh"]
    alias_re = re.compile(r"^\s*alias\s+(?:-\w\s+)?([A-Za-z0-9_.-]+)=")
    func_re = re.compile(r"^\s*(?:function\s+)?([A-Za-z0-9_.-]+)\s*\(\)\s*\{")
    for rc in rcs:
        if not rc.is_file():
            continue
        for line in rc.read_text(errors="replace").splitlines():
            for regex in (alias_re, func_re):
                m = regex.match(line)
                if m:
                    names.add(m.group(1))
    return names


def classify(entry: Entry, kind: str, opts, now: float, extra_names: set[str]) -> str | None:
    """The reason this entry would go, or None to keep it.

    Order is deliberate: a secret in a /tmp scratch command is reported
    as a secret, because that is the line you need to see.
    """
    text = entry.text
    passes = KIND_PASSES.get(kind, KIND_PASSES["bash"])

    if any(p.search(text) for p in opts.keep_patterns):
        return None

    if "secret" in passes and opts.secrets:
        if any(p.search(text) for p in SECRET_RE):
            return "secret"

    if "junk" in passes and opts.junk:
        if any(p.search(text) for p in JUNK_RE):
            return "junk"
        tokens = set(re.findall(r"[A-Za-z0-9_.]+", text.lower()))
        if tokens and tokens <= PLACEHOLDERS:
            return "junk"

    if "noise" in passes and opts.noise:
        squeezed = " ".join(text.split())
        if squeezed in NOISE_EXACT or any(p.match(text) for p in NOISE_RE):
            return "noise"
        if opts.aggressive and head_word(text) in AGGRESSIVE_HEADS:
            return "noise"

    if "unknown" in passes and opts.strip_unknown:
        if not known_command(head_word(text), extra_names):
            return "unknown"

    if "old" in passes and opts.days > 0 and entry.ts:
        if entry.ts < now - opts.days * 86400:
            return "old"

    return None


def plan(hist: HistoryFile, opts, extra_names: set[str]) -> None:
    """Mark every entry with its reason, in place.

    Duplicates are resolved back-to-front so the copy that survives is
    the most recent one: that is where Ctrl-R expects to find it, and it
    is the one whose timestamp still means something.
    """
    now = time.time()
    for entry in hist.entries:
        entry.reason = classify(entry, hist.kind, opts, now, extra_names)

    if opts.dedupe:
        seen: set[str] = set()
        for entry in reversed(hist.entries):
            if entry.reason is not None:
                continue
            if any(p.search(entry.text) for p in opts.keep_patterns):
                continue
            key = entry.text.strip()
            if key in seen:
                entry.reason = "duplicate"
            else:
                seen.add(key)

    if opts.keep_last > 0:
        survivors = [e for e in hist.entries if e.reason is None]
        for entry in survivors[: max(0, len(survivors) - opts.keep_last)]:
            entry.reason = "trimmed"


# ── Reporting ────────────────────────────────────────────────────────

def warn(msg: str) -> None:
    print(f"{T}stoa-history:{R} {msg}", file=sys.stderr)


def human(size: int) -> str:
    step = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if step < 1024 or unit == "GiB":
            return f"{step:.0f} {unit}" if unit == "B" else f"{step:.1f} {unit}"
        step /= 1024
    return f"{size} B"


def short(text: str, width: int = 62) -> str:
    one = " ".join(printable(text).split())
    return one if len(one) <= width else one[: width - 1] + "…"


def redact(text: str) -> str:
    """A secret must not be reprinted to a terminal that scrolls back.

    Only the program and its first flag survive; everything after is the
    part you are cleaning out.
    """
    tokens = printable(text).split()
    head = " ".join(tokens[:2]) if tokens else ""
    return short(head) + f" {S}… (redacted){R}"


def entries_word(n: int) -> str:
    return f"{n:,} " + ("entry" if n == 1 else "entries")


def tilde(path: Path) -> str:
    try:
        return "~/" + str(path.relative_to(HOME))
    except ValueError:
        return str(path)


def banner() -> None:
    print(f"\n  {B}╔══════════════════════════════════════════════════════════════╗{R}")
    print(f"  {B}║{R}  {F}STOA — History{R}                                              {B}║{R}")
    print(f"  {B}╚══════════════════════════════════════════════════════════════╝{R}")


def span_line(entries: list[Entry]) -> str | None:
    stamps = [e.ts for e in entries if e.ts]
    if not stamps:
        return None
    lo, hi = min(stamps), max(stamps)
    days = max(1, int((hi - lo) / 86400))
    fmt = "%Y-%m-%d"
    return (f"{time.strftime(fmt, time.localtime(lo))} → "
            f"{time.strftime(fmt, time.localtime(hi))}  ({days:,} days)")


def report_stats(hist: HistoryFile, opts, extra_names: set[str]) -> None:
    plan(hist, opts, extra_names)
    total = len(hist.entries)
    unique = len({e.text.strip() for e in hist.entries})
    counts = Counter(e.reason for e in hist.entries if e.reason)

    print(f"\n  {B}{tilde(hist.path)}{R}  {S}·{R}  {hist.kind}  {S}·{R}  "
          f"{entries_word(total)}  {S}·{R}  {human(hist.size)}")
    span = span_line(hist.entries)
    if span:
        print(f"    {S}span{R}       {span}")
    else:
        print(f"    {S}span{R}       {S}no timestamps in this file "
              f"(age pass cannot run){R}")
    dup_pct = 0 if not total else round(100 * (total - unique) / total)
    print(f"    {S}unique{R}     {unique:,}  {S}({dup_pct}% of the file is a repeat){R}")

    for reason in REASON_ORDER:
        if counts.get(reason):
            colour = T if reason == "secret" else F
            print(f"    {S}{REASON_LABEL[reason]:<10}{R} {colour}{counts[reason]:,}{R}")

    heads = Counter(printable(head_word(e.text)) for e in hist.entries
                    if head_word(e.text))
    if heads:
        print(f"\n    {S}most used programs{R}")
        for word, n in heads.most_common(5):
            print(f"      {n:>7,}  {F}{word}{R}")
    lines = Counter(" ".join(printable(e.text).split()) for e in hist.entries)
    if lines:
        print(f"    {S}most repeated lines{R}")
        for line, n in lines.most_common(5):
            if n < 2:
                break
            print(f"      {n:>7,}  {F}{short(line, 52)}{R}")


def report_clean(hist: HistoryFile, opts, extra_names: set[str]) -> tuple[int, int]:
    plan(hist, opts, extra_names)
    total = len(hist.entries)
    counts = Counter(e.reason for e in hist.entries if e.reason)
    keep = [e for e in hist.entries if e.reason is None]
    new_size = len(raw_bytes("".join(e.raw for e in keep)))

    print(f"\n  {B}{tilde(hist.path)}{R}  {S}·{R}  {hist.kind}  {S}·{R} "
          f"{entries_word(total)}")
    if not counts:
        print(f"    {O}nothing to prune{R}")
        return total, len(keep)

    for reason in REASON_ORDER:
        n = counts.get(reason, 0)
        if not n:
            continue
        colour = T if reason == "secret" else F
        print(f"    {S}{REASON_LABEL[reason]:<10}{R} {colour}{n:>6,}{R}")
        if opts.examples:
            shown = [e for e in hist.entries if e.reason == reason][-opts.examples:]
            for entry in shown:
                body = redact(entry.text) if reason == "secret" else short(entry.text)
                print(f"      {S}·{R} {S}{body}{R}")

    pct = 0 if not total else round(100 * (total - len(keep)) / total)
    print(f"    {S}{'─' * 26}{R}")
    print(f"    {S}keeping{R}    {O}{len(keep):,}{R} of {total:,}  {S}(−{pct}%){R}   "
          f"{S}{human(hist.size)} → {human(new_size)}{R}")
    if counts.get("secret"):
        print(f"    {T}a credential that reached this file is a credential to "
              f"rotate — removing the line is not revoking the key.{R}")
    return total, len(keep)


# ── Backup / write ───────────────────────────────────────────────────

def slug(path: Path) -> str:
    """Encode a full path into one filename.

    Backups used to be named after the basename alone, which is fine
    until you clean a second .bash_history from somewhere else and
    `restore` has no way to tell where either belongs.
    """
    text = str(path)
    # "!" is the separator, so a path that contains one already cannot be
    # decoded back exactly. Nothing writes such a history in practice, and
    # the backup itself is still correct — only its printed origin is.
    if text.startswith(str(HOME) + "/"):
        text = "~/" + text[len(str(HOME)) + 1:]
    return text.replace("/", "!")


def unslug(name: str) -> Path:
    text = name.replace("!", "/")
    return HOME / text[2:] if text.startswith("~/") else Path(text)


def backup(path: Path) -> Path:
    """Copy a file aside before it is written, and never onto another copy.

    The timestamp only resolves to the second, and `restore` takes its own
    safety copy of the file it is about to overwrite — in the same second
    as the backup it is restoring from. Without the suffix that second
    copy lands on the first one, and the restore then faithfully puts back
    the pruned file it just saved over the original.
    """
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = BACKUP_DIR / f"{slug(path)}.{stamp}.bak"
    n = 2
    while dest.exists():
        dest = BACKUP_DIR / f"{slug(path)}.{stamp}-{n}.bak"
        n += 1
    shutil.copy2(path, dest)
    # Prefix match rather than a glob: a history path may contain [ or *,
    # and a glob would then quietly match nothing and rotate nothing.
    prefix = slug(path) + "."
    old = sorted(q for q in BACKUP_DIR.iterdir()
                 if q.name.startswith(prefix) and q.name.endswith(".bak"))
    for stale in old[:-KEEP_BACKUPS]:
        stale.unlink(missing_ok=True)
    return dest


def apply_clean(hist: HistoryFile) -> Path:
    keep = [e for e in hist.entries if e.reason is None]
    dest = backup(hist.path)
    text = "".join(e.raw for e in keep)
    if text and not text.endswith("\n"):
        text += "\n"
    write_text(hist.path, text)
    return dest


# ── Commands ─────────────────────────────────────────────────────────

def detect(opts) -> list[tuple[str, Path]]:
    if opts.file:
        out = []
        for name in opts.file:
            path = Path(name).expanduser()
            if not path.is_file():
                warn(f"{path}: no such file")
                continue
            out.append((opts.shell or guess_kind(path), path))
        return out
    candidates = list(SHELL_FILES)
    if opts.include_repl:
        candidates += REPL_FILES
    return [(kind, p) for kind, p in candidates if p.is_file() and p.stat().st_size > 0]


def guess_kind(path: Path) -> str:
    name = path.name
    if "zsh" in name or name == ".histfile":
        return "zsh"
    if "bash" in name:
        return "bash"
    if any(name == p.name for _, p in REPL_FILES):
        return "repl"
    head = read_text(path)[:2000]
    return "zsh" if ZSH_LINE.match(head.splitlines()[0] if head.splitlines() else "") else "bash"


def report_foreign() -> None:
    found = [(name, path, hint) for name, path, hint in FOREIGN_FILES if path.exists()]
    if not found:
        return
    print(f"\n  {S}left alone (own format, own tooling){R}")
    for name, path, hint in found:
        print(f"    {S}·{R} {F}{name}{R} {S}{tilde(path)} — {hint}{R}")


def cmd_stats(opts) -> int:
    banner()
    files = detect(opts)
    if not files:
        warn("no history files found")
        return 1
    extra = rc_names() if opts.strip_unknown else set()
    for kind, path in files:
        report_stats(load(kind, path), opts, extra)
    report_foreign()
    print(f"\n  {S}`stoa-history clean` shows what a prune would remove.{R}\n")
    return 0


def cmd_clean(opts) -> int:
    banner()
    files = detect(opts)
    if not files:
        warn("no history files found")
        return 1
    extra = rc_names() if opts.strip_unknown else set()
    loaded = [load(kind, path) for kind, path in files]
    removed_any = False
    for hist in loaded:
        before, after = report_clean(hist, opts, extra)
        removed_any = removed_any or before != after
    report_foreign()

    if not removed_any:
        print(f"\n  {O}Nothing to do.{R}\n")
        return 0
    if not opts.apply:
        print(f"\n  {B}Dry run — nothing was written.{R} "
              f"{S}Re-run with --apply to prune.{R}\n")
        return 0
    if not opts.yes and sys.stdin.isatty():
        answer = input(f"\n  {B}Prune these files?{R} [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print(f"  {S}Left untouched.{R}\n")
            return 0

    print()
    for hist in loaded:
        if all(e.reason is None for e in hist.entries):
            continue
        dest = apply_clean(hist)
        print(f"  {O}✓{R} {tilde(hist.path)}  {S}backup: {tilde(dest)}{R}")
    print(f"\n  {S}A shell already running still holds the old list in memory and{R}")
    print(f"  {S}writes it back when it exits. Open a new terminal, or run{R}")
    print(f"  {S}`history -r` (bash) / `fc -R` (zsh) in the ones you keep.{R}\n")
    return 0


def cmd_suggest(opts) -> int:
    banner()
    files = detect(opts)
    if not files:
        warn("no history files found")
        return 1
    lines: Counter[str] = Counter()
    for kind, path in files:
        if kind == "repl":
            continue
        for entry in load(kind, path).entries:
            one = " ".join(entry.text.split())
            if len(one) >= 10 and "\n" not in entry.text:
                lines[one] += 1

    taken = rc_names()
    suggestions: list[tuple[str, str, int]] = []
    for line, count in lines.most_common(300):
        if count < opts.min_count or len(suggestions) >= opts.top:
            break
        if any(p.search(line) for p in SECRET_RE):
            continue  # an alias is a worse place for a token than history is
        words = [w for w in re.findall(r"[A-Za-z][A-Za-z0-9_-]*", line)][:3]
        if not words:
            continue
        name = "".join(w[0] for w in words).lower()
        candidate, n = name, 2
        while candidate in taken or shutil.which(candidate):
            candidate = f"{name}{n}"
            n += 1
        taken.add(candidate)
        suggestions.append((candidate, line, count))

    if not suggestions:
        print(f"\n  {S}Nothing typed often enough yet (threshold: "
              f"{opts.min_count} times).{R}\n")
        return 0
    print(f"\n  {S}Typed often enough to deserve a shorter name. Paste what you{R}")
    print(f"  {S}want into ~/.bashrc or ~/.zshrc — nothing is written for you.{R}\n")
    for name, line, count in suggestions:
        print(f"    {S}{count:>5,}×{R}  {B}alias {name}={R}{F}'{line}'{R}")
    print()
    return 0


def cmd_restore(opts) -> int:
    banner()
    backups = sorted(BACKUP_DIR.glob("*.bak")) if BACKUP_DIR.is_dir() else []
    if not backups:
        print(f"\n  {S}No backups under {tilde(BACKUP_DIR)}.{R}\n")
        return 1
    if opts.list:
        print(f"\n  {S}{tilde(BACKUP_DIR)}{R}")
        for path in backups:
            when = time.strftime("%Y-%m-%d %H:%M", time.localtime(path.stat().st_mtime))
            origin = tilde(unslug(path.name.rsplit(".", 2)[0]))
            print(f"    {F}{path.name}{R}\n      {S}{when}  "
                  f"{human(path.stat().st_size)}  → {origin}{R}")
        print()
        return 0

    # Newest backup per original file — the list is sorted by name, and the
    # timestamp sits just before .bak, so the last one to land wins.
    newest: dict[str, Path] = {}
    for path in backups:
        newest[path.name.rsplit(".", 2)[0]] = path

    if opts.name:
        chosen = BACKUP_DIR / opts.name
        if not chosen.is_file():
            warn(f"{opts.name}: no such backup (try --list)")
            return 1
        newest = {chosen.name.rsplit(".", 2)[0]: chosen}

    print()
    for name, src in sorted(newest.items()):
        dest = unslug(name)
        if not opts.yes and sys.stdin.isatty():
            answer = input(f"  Restore {tilde(src)} → {tilde(dest)}? [y/N] ").strip().lower()
            if answer not in ("y", "yes"):
                continue
        # The file being overwritten is itself worth a copy: a restore is as
        # destructive as the prune it undoes, and this makes it reversible.
        safety = backup(dest) if dest.exists() else None
        shutil.copy2(src, dest)
        print(f"  {O}✓{R} {tilde(dest)}  {S}from {src.name}{R}")
        if safety:
            print(f"    {S}what was there is now {safety.name}{R}")
    print()
    return 0


# ── CLI ──────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="stoa-history",
        description="Analyse and prune shell history. Nothing is written "
                    "without --apply, and every write is backed up first.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Keep list: ~/.config/stoa/history-keep (one regex per line).",
    )
    sub = parser.add_subparsers(dest="command")

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--file", action="append", metavar="PATH",
                       help="history file to work on (repeatable); default is "
                            "every one found under $HOME")
        p.add_argument("--shell", choices=("bash", "zsh", "repl"),
                       help="format of --file, when the name does not give it away")
        p.add_argument("--include-repl", action="store_true",
                       help="also read the python/node/mysql/psql/sqlite histories")
        p.add_argument("--days", type=int, default=365, metavar="N",
                       help="drop timestamped entries older than N days "
                            "(0 disables; default: 365)")
        p.add_argument("--keep-last", type=int, default=0, metavar="N",
                       help="cap the file at N most recent entries (0 disables)")
        p.add_argument("--no-dedupe", dest="dedupe", action="store_false",
                       help="keep repeated commands")
        p.add_argument("--no-noise", dest="noise", action="store_false",
                       help="keep ls / cd .. / clear and friends")
        p.add_argument("--no-junk", dest="junk", action="store_false",
                       help="keep /tmp scratch and foo/bar placeholders")
        p.add_argument("--no-secrets", dest="secrets", action="store_false",
                       help="keep lines carrying tokens and passwords")
        p.add_argument("--aggressive", action="store_true",
                       help="also treat every ls/cd/cat/echo/man line as noise")
        p.add_argument("--strip-unknown", action="store_true",
                       help="drop lines whose first word is no program on this "
                            "machine (typos, and anything you uninstalled)")
        p.add_argument("--examples", type=int, default=3, metavar="N",
                       help="show N examples per class (0 for none; default: 3)")

    p_stats = sub.add_parser("stats", help="what is in your history (default)")
    common(p_stats)

    p_clean = sub.add_parser("clean", help="prune it (dry run without --apply)")
    common(p_clean)
    p_clean.add_argument("--apply", action="store_true",
                         help="write the pruned files, after backing them up")
    p_clean.add_argument("-y", "--yes", action="store_true",
                         help="skip the confirmation prompt")

    p_suggest = sub.add_parser("suggest", help="aliases worth having")
    common(p_suggest)
    p_suggest.add_argument("--min-count", type=int, default=5, metavar="N",
                           help="how many times a line must appear (default: 5)")
    p_suggest.add_argument("--top", type=int, default=12, metavar="N",
                           help="how many aliases to propose (default: 12)")

    p_restore = sub.add_parser("restore", help="put a backup back")
    p_restore.add_argument("name", nargs="?", metavar="BACKUP",
                           help="a backup filename from --list; the newest one "
                                "per file is used when omitted")
    p_restore.add_argument("--list", action="store_true", help="only list the backups")
    p_restore.add_argument("-y", "--yes", action="store_true",
                           help="skip the confirmation prompt")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = list(argv)
    # No subcommand (or straight to the options) means `stats`.
    if not args or (args[0].startswith("-") and args[0] not in ("-h", "--help")):
        args = ["stats"] + args
    opts = parser.parse_args(args)
    if opts.command != "restore":
        opts.keep_patterns = load_keep_patterns()
    handlers = {
        "stats": cmd_stats,
        "clean": cmd_clean,
        "suggest": cmd_suggest,
        "restore": cmd_restore,
    }
    return handlers[opts.command](opts)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print()
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
