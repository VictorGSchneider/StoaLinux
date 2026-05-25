#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Wallpaper Generator                           ║
# ║                                                              ║
# ║  Renders four Stoa themes via GLSL fragment shaders          ║
# ║  (theme/shaders/<theme>.frag) using glslViewer in headless   ║
# ║  mode. The shaders do the heavy lifting (Perlin/fBm noise,   ║
# ║  domain warping, real lighting) — far beyond what            ║
# ║  ImageMagick's `plasma:` primitive could produce.            ║
# ║                                                              ║
# ║  Themes (visual identity, always the four):                 ║
# ║    marble    — domain-warped fBm with accent veining         ║
# ║    parchment — warm gradient + horizon glow                  ║
# ║    columns   — vertical column silhouettes                   ║
# ║    memento   — soft texture + MEMENTO MORI text + the quote  ║
# ║                                                              ║
# ║  Modes:                                                      ║
# ║    defaults — one wallpaper per theme, fixed seed (kept as   ║
# ║               marble.png/parchment.png/columns.png/          ║
# ║               memento.png; hyprland.conf hardcodes those).   ║
# ║    quotes   — one wallpaper per theme per quote, seeded by   ║
# ║               SHA1(quote). Idempotent.                       ║
# ║                                                              ║
# ║  Requires: glslviewer, imagemagick (memento text only), jq   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ── Config ──
WALLDIR="${HOME}/.config/stoa/wallpapers"
SHADER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/shaders"
QUOTES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/quotes.json"
WIDTH=1920
HEIGHT=1080

THEMES=(marble parchment columns memento)

# ── ImageMagick (text overlay on memento only) ──
if command -v magick &>/dev/null; then IM=(magick)
elif command -v convert &>/dev/null; then IM=(convert)
else IM=(); fi

# ── Dependency check ──
_require_glslviewer() {
    if ! command -v glslViewer &>/dev/null; then
        echo "stoa-walls: glslViewer not installed. Install: yay -S glslviewer" >&2
        exit 1
    fi
}

# ── Helpers ──

_hash8() { printf '%s' "$1" | sha1sum | head -c 8; }

_seed_from_hash() {
    local h="$1"
    # 8 hex chars → unsigned int, modulo 100000 keeps the float
    # uniform in GLSL well-behaved (no precision loss).
    printf '%d' "0x$h" | awk '{print ($1<0?-$1:$1) % 100000}'
}

# Render one shader headlessly. glslViewer's headless mode renders a
# single frame, takes a screenshot, then exits. Some versions accept
# multiple -e flags, others use semicolons inside a single -e — try
# both, fall back gracefully.
_render_shader() {
    local theme=$1 seed=$2 out=$3
    local shader="${SHADER_DIR}/${theme}.frag"
    [ -f "$shader" ] || { echo "  [!] missing shader: $shader" >&2; return 1; }

    glslViewer \
        --headless \
        -w "$WIDTH" -h "$HEIGHT" \
        -e "u_seed,${seed}" \
        -e "screenshot,${out}" \
        -e "exit" \
        "$shader" >/dev/null 2>&1
}

# Composite text on top of a memento wallpaper. Done after the shader
# because GLSL has no text rendering; ImageMagick has good kerning + font fallback.
_overlay_memento_text() {
    local png=$1 quote=$2
    [ ${#IM[@]} -eq 0 ] && return 0
    local font=""
    for f in "EB Garamond" "EB-Garamond" "DejaVu Serif" "serif"; do
        if "${IM[@]}" -list font 2>/dev/null | grep -qiE "^[[:space:]]*(Font:[[:space:]]*)?${f}\$"; then
            font="$f"; break
        fi
    done
    local args=("$png" -gravity center)
    [ -n "$font" ] && args+=(-font "$font")
    args+=(
        -pointsize 96 -fill "#c49a5c66" -annotate +0-160 "MEMENTO MORI"
    )
    if [ -n "$quote" ]; then
        args+=(
            '('
                -size 1200x300 -background none -gravity center
                -fill "#a89f91"
        )
        [ -n "$font" ] && args+=(-font "$font")
        args+=(
                -pointsize 28 "caption:${quote}"
            ')'
            -geometry +0+80 -compose Over -composite
        )
    fi
    args+=("$png")
    "${IM[@]}" "${args[@]}" 2>/dev/null || true
}

_render_set() {
    local seed=$1 prefix=$2 quote="${3:-}"
    local i theme out
    for ((i=0; i<${#THEMES[@]}; i++)); do
        theme="${THEMES[$i]}"
        out="${WALLDIR}/${prefix}-${theme}.png"
        if [ -f "$out" ] && [ -z "${STOA_WALLS_FORCE:-}" ]; then continue; fi
        # Bump the seed per theme so accent picks differ even within a set.
        local theme_seed=$((seed + i * 137))
        if _render_shader "$theme" "$theme_seed" "$out"; then
            if [ "$theme" = "memento" ]; then
                _overlay_memento_text "$out" "$quote"
            fi
            echo "  [+] $(basename "$out")"
        else
            echo "  [!] failed: ${theme} prefix=${prefix}" >&2
        fi
    done
}

# ── CLI ──

cmd_defaults() {
    _require_glslviewer
    mkdir -p "$WALLDIR"
    echo "Generating default wallpapers (one per theme)..."
    STOA_WALLS_FORCE=1
    local i theme out
    for ((i=0; i<${#THEMES[@]}; i++)); do
        theme="${THEMES[$i]}"
        out="${WALLDIR}/${theme}.png"
        local seed=$((42 + i * 137))
        if _render_shader "$theme" "$seed" "$out"; then
            if [ "$theme" = "memento" ]; then
                _overlay_memento_text "$out" "Memento mori. — Stoa Linux"
            fi
            echo "  [+] ${theme}.png"
        else
            echo "  [!] failed: ${theme}" >&2
        fi
    done
    echo "Done. → $WALLDIR"
}

cmd_quotes() {
    _require_glslviewer
    mkdir -p "$WALLDIR"
    if ! command -v jq &>/dev/null; then
        echo "stoa-walls: jq required. Install: sudo pacman -S jq" >&2; exit 1
    fi
    if [ ! -f "$QUOTES_FILE" ]; then
        echo "stoa-walls: no quotes file at $QUOTES_FILE" >&2
        echo "            Run stoa-quotes-sync first." >&2
        exit 1
    fi
    local limit="${1:-0}"
    local total=$(jq 'length' "$QUOTES_FILE")
    local done=0
    echo "Generating ${#THEMES[@]} wallpapers per quote (${total} quotes)..."
    while IFS= read -r quote; do
        [ -z "$quote" ] && continue
        local hash=$(_hash8 "$quote")
        local seed=$(_seed_from_hash "$hash")
        _render_set "$seed" "quote-${hash}" "$quote"
        done=$((done+1))
        [ "$limit" -gt 0 ] && [ "$done" -ge "$limit" ] && break
    done < <(jq -r '.[]' "$QUOTES_FILE")
    echo "Done. $(find "$WALLDIR" -maxdepth 1 -name 'quote-*.png' | wc -l) quote wallpapers in $WALLDIR"
}

cmd_clean() {
    [ -d "$WALLDIR" ] || return 0
    find "$WALLDIR" -maxdepth 1 -name 'quote-*.png' -delete
    echo "Cleaned quote wallpapers."
}

cmd_regen() {
    cmd_clean
    cmd_quotes "$@"
}

cmd_help() {
    cat <<EOF
Usage: stoa-walls <command> [args]

Themes:    ${THEMES[*]}
Shaders:   $SHADER_DIR
Output:    $WALLDIR
Quotes:    $QUOTES_FILE

Commands:
  defaults          One wallpaper per theme, fixed seed (marble.png,
                    parchment.png, columns.png, memento.png).
                    hyprland.conf hardcodes marble.png.
  quotes [N]        Render one wallpaper per theme per quote, seeded
                    by SHA1(quote). Optional N caps how many quotes.
  regen [N]         clean + quotes.
  clean             Remove generated quote-*.png (keeps defaults).
  help              This text.

No args = defaults + quotes.

Requires: glslviewer (AUR), imagemagick, jq.
EOF
}

case "${1:-}" in
    defaults) shift; cmd_defaults "$@" ;;
    quotes)   shift; cmd_quotes "$@" ;;
    regen)    shift; cmd_regen "$@" ;;
    clean)    shift; cmd_clean "$@" ;;
    help|--help|-h) cmd_help ;;
    "")       cmd_defaults; echo; cmd_quotes ;;
    *)        echo "stoa-walls: unknown command: $1" >&2; cmd_help >&2; exit 2 ;;
esac
