#!/bin/bash
# ╔═══════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Vendor Sync                                   ║
# ║  Pull upstream commits into scripts/vendor/<name> and show   ║
# ║  the diff against the Stoa fork so you can forward-port.     ║
# ╚═══════════════════════════════════════════════════════════╝
#
# Usage:
#   scripts/vendor/sync-upstream.sh <vendor-name>
#   scripts/vendor/sync-upstream.sh brcs
#   scripts/vendor/sync-upstream.sh dfm
#
# Add new vendored projects to the VENDORS table below.

set -euo pipefail

# name|prefix|upstream-url|branch|stoa-fork-path (relative to repo root)
# Leave the fork path empty when the vendor has no single-file Stoa fork
# (e.g. a Python package vendored for reference only).
VENDORS=(
    "brcs|scripts/vendor/brcs|https://github.com/VictorGSchneider/BRCS.sh.git|main|scripts/stoa-maintain.sh"
    "dfm|scripts/vendor/dfm|https://github.com/VictorGSchneider/DFM.git|main|"
)

B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
F='\033[38;2;212;207;196m'
R='\033[0m'

_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || {
        echo "sync-upstream: not inside a git repo" >&2
        exit 1
    }
}

_find_vendor() {
    local name="$1"
    for row in "${VENDORS[@]}"; do
        IFS='|' read -r n prefix url branch fork <<< "$row"
        if [ "$n" = "$name" ]; then
            printf '%s|%s|%s|%s\n' "$prefix" "$url" "$branch" "$fork"
            return 0
        fi
    done
    return 1
}

_usage() {
    echo -e "${F}Usage:${R} $0 <vendor-name>"
    echo ""
    echo -e "${F}Available vendors:${R}"
    for row in "${VENDORS[@]}"; do
        IFS='|' read -r n prefix url branch fork <<< "$row"
        echo -e "  ${B}${n}${R}  ${S}→ ${prefix} (from ${url}#${branch})${R}"
    done
}

main() {
    local name="${1:-}"
    if [ -z "$name" ] || [ "$name" = "-h" ] || [ "$name" = "--help" ]; then
        _usage
        exit 0
    fi

    local info
    if ! info=$(_find_vendor "$name"); then
        echo -e "${T}sync-upstream: unknown vendor '${name}'${R}" >&2
        _usage
        exit 1
    fi

    IFS='|' read -r prefix url branch fork <<< "$info"
    local root; root=$(_repo_root)
    cd "$root"

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo -e "${T}Working tree is dirty. Commit or stash before syncing.${R}" >&2
        exit 1
    fi

    if [ ! -d "$prefix" ]; then
        echo -e "${F}First-time import — running 'git subtree add'…${R}"
        git subtree add --prefix="$prefix" "$url" "$branch" --squash
        echo -e "${O}[+] Subtree added at ${prefix}${R}"
    else
        echo -e "${F}Pulling ${url}#${branch} into ${prefix}…${R}"
        git subtree pull --prefix="$prefix" "$url" "$branch" --squash
        echo -e "${O}[+] Subtree updated${R}"
    fi

    if [ -n "$fork" ] && [ -f "$fork" ]; then
        echo ""
        echo -e "${F}Diff summary — Stoa fork vs. vendored upstream:${R}"
        echo -e "${S}  (fork: ${fork})${R}"
        echo -e "${S}  (upstream copy: ${prefix}/$(basename "$fork" | sed 's/^stoa-maintain\.sh$/BRCS.sh/'))${R}"
        echo ""
        # Best-effort: show the diffstat only. Full diff stays out of stdout
        # so the user can pipe it through `less` or `delta` separately.
        local upstream_file
        upstream_file="${prefix}/$(basename "$fork" | sed 's/^stoa-maintain\.sh$/BRCS.sh/')"
        if [ -f "$upstream_file" ]; then
            diff -u "$upstream_file" "$fork" | diffstat -p0 2>/dev/null \
                || diff --brief "$upstream_file" "$fork" \
                || true
            echo ""
            echo -e "${S}Full diff: diff -u ${upstream_file} ${fork}${R}"
        fi
    else
        echo ""
        echo -e "${S}No Stoa fork configured for ${name} — skipping diff summary.${R}"
    fi

    echo ""
    echo -e "${O}Done. Review any incoming changes and forward-port bug fixes${R}"
    if [ -n "$fork" ]; then
        echo -e "${O}into ${fork} as needed, then commit.${R}"
    else
        echo -e "${O}into the matching Stoa sources as needed, then commit.${R}"
    fi
}

main "$@"
