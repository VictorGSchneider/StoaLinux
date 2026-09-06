#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Check runner                                  ║
# ║  "Only what serves, stays."                                  ║
# ║                                                              ║
# ║  The single entry point for every check in this repo. CI     ║
# ║  runs exactly this, so `bash tests/run.sh` before a push     ║
# ║  tells you what CI will say — no copying commands out of a   ║
# ║  workflow file.                                              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE
#   tests/run.sh                 # every group
#   tests/run.sh shell           # one group (shell | data | stoa)
#   tests/run.sh --strict        # a missing tool fails instead of skipping
#   tests/run.sh --list          # show the groups and their checks
#
# GROUPS
#   shell  syntax and shellcheck over every script we ship
#   data   the formats a typo silently breaks: JSON, TOML, Lua/Luau, Python
#   stoa   the repo-specific invariants under tests/check_*.py and test_*.sh

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

if [ -t 1 ]; then
    B=$'\033[38;2;196;154;92m'; O=$'\033[38;2;138;154;108m'
    T=$'\033[38;2;179;107;90m'; S=$'\033[38;2;110;106;98m'; R=$'\033[0m'
else
    B=""; O=""; T=""; S=""; R=""
fi

STRICT=0
RUN_GROUPS=()
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        --list)
            printf '%s\n' "shell  bash -n, shellcheck" \
                          "data   JSON, TOML, Lua/Luau, Python" \
                          "stoa   menu dispatch, shell pitfalls, config integrity, profile unseed"
            exit 0 ;;
        -h|--help) sed -n '15,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        shell|data|stoa) RUN_GROUPS+=("$arg") ;;
        *) echo "run.sh: unknown argument: $arg (try --help)" >&2; exit 2 ;;
    esac
done
[ ${#RUN_GROUPS[@]} -eq 0 ] && RUN_GROUPS=(shell data stoa)

# ── What counts as ours ──────────────────────────────────────────────
# One definition, used by every check. scripts/vendor/** is upstream code
# we forward-port rather than own, so it is excluded everywhere — see
# scripts/vendor/README.md.
_ours() {
    find . -type f -not -path './.git/*' -not -path './scripts/vendor/*' "$@"
}

# *.sh plus the extensionless scripts (stoa-drive-pin, stoa-doctor-status,
# the pacman hooks) — they are installed and run like the rest.
mapfile -t SH_FILES < <(
    {
        _ours -name '*.sh'
        _ours ! -name '*.*' -exec sh -c \
            'head -c 40 "$1" | grep -qE "^#!.*(bash|/sh)"' _ {} \; -print
    } | sort -u
)
mapfile -t JSON_FILES < <(_ours -name '*.json' | sort)
mapfile -t TOML_FILES < <(_ours -name '*.toml' | sort)
mapfile -t LUA_FILES  < <(_ours \( -name '*.lua' -o -name '*.luau' \) | sort)
mapfile -t PY_FILES   < <(_ours -name '*.py' | sort)

PASS=0; FAIL=0; SKIP=0; FAILED=()

# report <name> <status> [output]
_report() {
    local name="$1" status="$2" output="${3:-}"
    case "$status" in
        ok)   PASS=$((PASS + 1)); printf '  %s✓%s %s\n' "$O" "$R" "$name" ;;
        skip) SKIP=$((SKIP + 1)); printf '  %s~%s %s %s(%s)%s\n' "$S" "$R" "$name" "$S" "$output" "$R"
              [ "$STRICT" -eq 1 ] && { FAIL=$((FAIL + 1)); FAILED+=("$name (skipped under --strict)"); } ;;
        *)    FAIL=$((FAIL + 1)); FAILED+=("$name"); printf '  %s✕%s %s\n' "$T" "$R" "$name"
              [ -n "$output" ] && printf '%s\n' "$output" | sed 's/^/      /' ;;
    esac
    return 0
}

# run <name> <command...> — ok when the command exits 0
_run() {
    local name="$1"; shift
    local output
    if output=$("$@" 2>&1); then _report "$name" ok
    else _report "$name" fail "$output"; fi
}

# needs <tool> <name> <hint> — skip the check when the tool is absent
_needs() {
    command -v "$1" >/dev/null 2>&1 && return 0
    _report "$2" skip "install $3"
    return 1
}

# ── shell ────────────────────────────────────────────────────────────
group_shell() {
    printf '\n%sshell%s %s(%d files)%s\n' "$B" "$R" "$S" "${#SH_FILES[@]}" "$R"

    local bad=() f
    for f in "${SH_FILES[@]}"; do
        bash -n "$f" 2>/dev/null || bad+=("$f")
    done
    if [ ${#bad[@]} -eq 0 ]; then _report "syntax (bash -n)" ok
    else _report "syntax (bash -n)" fail "$(printf '%s\n' "${bad[@]}")"; fi

    _needs shellcheck "shellcheck" "shellcheck" || return 0

    # The floor is `warning` minus the patterns this tree uses on purpose:
    #   SC2155 local x=$(...)   SC2034 palette constants read by eye
    #   SC1090/SC1091 sourced paths only known at runtime
    #   SC2024 sudo with a redirect that lands in $HOME anyway
    #   SC2178/SC2154/SC2064/SC2043/SC2038 checked by hand, all deliberate
    # Anything outside that list is a new class and should fail.
    _run "shellcheck (warning)" \
        shellcheck --shell=bash --severity=warning \
        --exclude=SC2155,SC2034,SC1090,SC1091,SC2024,SC2178,SC2154,SC2064,SC2043,SC2038 \
        "${SH_FILES[@]}"

    # Every stoa menu dispatches on unanchored substrings, so a case
    # pattern can shadow a later, more specific one — that is how
    # "15 minutes" silently became 5. These two are warnings, so they need
    # naming even though the floor above already sits at warning.
    _run "shellcheck (case shadowing)" \
        shellcheck --shell=bash --severity=warning --include=SC2221,SC2222 \
        "${SH_FILES[@]}"
}

# ── data ─────────────────────────────────────────────────────────────
group_data() {
    printf '\n%sdata%s %s(%d json, %d toml, %d lua, %d py)%s\n' "$B" "$R" "$S" \
        "${#JSON_FILES[@]}" "${#TOML_FILES[@]}" "${#LUA_FILES[@]}" "${#PY_FILES[@]}" "$R"

    _run "json" python3 -c '
import json, sys
for f in sys.argv[1:]:
    with open(f) as fh:
        json.load(fh)
' "${JSON_FILES[@]}"

    # A broken plugin.toml does not raise anything — Noctalia just never
    # loads that widget, and config.toml is the whole shell config.
    _run "toml" python3 -c '
import sys, tomllib
for f in sys.argv[1:]:
    with open(f, "rb") as fh:
        tomllib.load(fh)
' "${TOML_FILES[@]}"

    # config/hypr/hyprland.lua is the Hyprland config (0.55+ dropped
    # hyprlang for lua): a syntax error there and the compositor refuses to
    # load any config at all. *.luau are the Noctalia v5 plugins — Luau is a
    # superset of Lua 5.1, so luac only parses the common subset they stick
    # to, which catches ordinary syntax errors, not Luau types.
    if _needs luac5.4 "lua/luau syntax" "lua5.4"; then
        local bad=() f
        for f in "${LUA_FILES[@]}"; do
            luac5.4 -p "$f" >/dev/null 2>&1 || bad+=("$f")
        done
        rm -f luac.out
        if [ ${#bad[@]} -eq 0 ]; then _report "lua/luau syntax" ok
        else _report "lua/luau syntax" fail "$(printf '%s\n' "${bad[@]}")"; fi
    fi

    _run "python (compile)" python3 -m py_compile "${PY_FILES[@]}"

    # py_compile only proves it parses. These rules are the ones that bite
    # at runtime: undefined names, redefinitions, and F601 — a dict key
    # written twice, which silently drops the first entry and is exactly
    # how stoa-predict.py lost two emoji.
    if _needs ruff "python (ruff)" "pip install ruff"; then
        _run "python (ruff)" ruff check --no-cache --isolated --quiet \
            --select E9,F63,F7,F82,F811,F601,F602 "${PY_FILES[@]}"
    fi
}

# ── stoa ─────────────────────────────────────────────────────────────
group_stoa() {
    printf '\n%sstoa%s %sinvariants%s\n' "$B" "$R" "$S" "$R"
    local f
    for f in tests/check_*.py; do
        [ -e "$f" ] || continue
        _run "$(basename "$f" .py | sed 's/^check_/check: /; s/_/ /g')" python3 "$f"
    done
    for f in tests/test_*.sh; do
        [ -e "$f" ] || continue
        _run "$(basename "$f" .sh | sed 's/^test_/test: /; s/_/ /g')" bash "$f"
    done
}

for g in "${RUN_GROUPS[@]}"; do "group_$g"; done

printf '\n%s%d passed%s' "$O" "$PASS" "$R"
[ "$SKIP" -gt 0 ] && printf ', %s%d skipped%s' "$S" "$SKIP" "$R"
[ "$FAIL" -gt 0 ] && printf ', %s%d failed%s' "$T" "$FAIL" "$R"
printf '\n'
if [ "$FAIL" -gt 0 ]; then
    printf '\n%sfailed:%s\n' "$T" "$R"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
