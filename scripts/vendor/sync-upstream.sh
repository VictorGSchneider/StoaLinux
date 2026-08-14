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
# The fork path may be either a single file (like scripts/stoa-maintain.sh
# for brcs) or a directory (like scripts/stoa-dfm for dfm). Leave it empty
# only when the vendor has no Stoa fork at all.
VENDORS=(
    "brcs|scripts/vendor/brcs|https://github.com/VictorGSchneider/BRCS.sh.git|main|scripts/stoa-maintain.sh"
    "dfm|scripts/vendor/dfm|https://github.com/VictorGSchneider/DFM.git|main|scripts/stoa-dfm"
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
        # Single-file fork (e.g. brcs → scripts/stoa-maintain.sh).
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
    elif [ -n "$fork" ] && [ -d "$fork" ]; then
        # Directory fork (e.g. dfm → scripts/stoa-dfm). Compare against the
        # matching subtree of the vendored upstream: diff only the paths that
        # also exist in the fork, so unrelated top-level upstream files
        # (LICENSE, README, screenshots/, …) don't pollute the summary.
        echo ""
        echo -e "${F}Diff summary — Stoa fork vs. vendored upstream:${R}"
        echo -e "${S}  (fork:           ${fork}/)${R}"
        echo -e "${S}  (upstream copy:  ${prefix}/)${R}"
        echo ""
        # Enumerate fork entries and diff each against the vendored copy.
        # -N treats missing files as empty, so additions show up cleanly.
        local entry upstream_entry
        local any_diff=0
        while IFS= read -r -d '' entry; do
            local rel="${entry#"$fork"/}"
            upstream_entry="${prefix}/${rel}"
            if [ -e "$upstream_entry" ] || [ -e "$entry" ]; then
                if ! diff -urN "$upstream_entry" "$entry" >/dev/null 2>&1; then
                    any_diff=1
                    diff -urN "$upstream_entry" "$entry" | diffstat -p0 2>/dev/null \
                        || diff --brief -r "$upstream_entry" "$entry" \
                        || true
                fi
            fi
        done < <(find "$fork" -mindepth 1 -maxdepth 1 -print0)
        if [ "$any_diff" -eq 0 ]; then
            echo -e "${S}(fork is identical to upstream)${R}"
        fi
        echo ""
        echo -e "${S}Full diff: diff -urN ${prefix} ${fork}${R}"
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
