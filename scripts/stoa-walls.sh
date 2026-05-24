#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Wallpaper Generator                           ║
# ║  Generates wallpapers built on four Stoa themes, with a     ║
# ║  seeded abstract layer on top.                               ║
# ║                                                              ║
# ║  Themes (visual identity, always the four):                 ║
# ║    marble    — plasma marble texture + veining               ║
# ║    parchment — warm gradient + horizon glow                  ║
# ║    columns   — vertical column silhouettes on sky            ║
# ║    memento   — subtle MEMENTO MORI + the quote itself        ║
# ║                                                              ║
# ║  Modes:                                                      ║
# ║    defaults — one wallpaper per theme, fixed seed (kept as   ║
# ║               marble.png, parchment.png, columns.png,        ║
# ║               memento.png — hyprland.conf hardcodes these).  ║
# ║    quotes   — one wallpaper per theme per quote, seeded by   ║
# ║               SHA1(quote). Idempotent.                       ║
# ║                                                              ║
# ║  Requires: imagemagick, jq                                   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ── Config ──
WALLDIR="${HOME}/.config/stoa/wallpapers"
QUOTES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/quotes.json"
WIDTH=1920
HEIGHT=1080

# ── Palette ──
BG="#211e19"
BG2="#1a1714"
BG_LIGHT="#2d2921"
FG="#d4cfc4"
FG_DIM="#a89f91"
BRONZE="#c49a5c"
GOLD="#d4a84b"
OLIVE="#8a9a6c"
TERRACOTTA="#b36b5a"
STONE="#6e6a62"

ACCENTS=("$BRONZE" "$GOLD" "$OLIVE" "$TERRACOTTA")

THEMES=(marble parchment columns memento)
ABSTRACTS=(veins orbs particles glow)

# ── ImageMagick ──
if command -v magick &>/dev/null; then IM=(magick)
elif command -v convert &>/dev/null; then IM=(convert)
else
    echo "stoa-walls: ImageMagick not found. Install: sudo pacman -S imagemagick" >&2
    exit 1
fi

_pick_font() {
    local candidates=("EB Garamond" "EB-Garamond" "DejaVu Serif" "serif" "JetBrains Mono")
    for f in "${candidates[@]}"; do
        if "${IM[@]}" -list font 2>/dev/null | grep -qiE "^[[:space:]]*(Font:[[:space:]]*)?${f}\$"; then
            echo "$f"; return
        fi
    done
    echo ""
}
FONT=$(_pick_font)

# ── Helpers ──

_hash8() { printf '%s' "$1" | sha1sum | head -c 8; }

_seed_from_hash() {
    local h="$1"
    printf '%d' "0x$h" | awk '{print ($1<0?-$1:$1) % 2147483647}'
}

_pick_abstract() {
    local seed=$1
    echo "${ABSTRACTS[$(( seed % ${#ABSTRACTS[@]} ))]}"
}

_pick_accent() {
    local seed=$1
    echo "${ACCENTS[$(( seed % ${#ACCENTS[@]} ))]}"
}

# ── Abstract overlays ──
# Each appends IM args to the global ARGS array. They expect:
#   $1 = seed (int), $2 = accent (color)
# and use $WIDTH/$HEIGHT/palette from the global scope.

_overlay_veins() {
    local seed=$1 accent=$2
    ARGS+=(
        '('
            -size "${WIDTH}x${HEIGHT}" -seed "$((seed + 11))" plasma:
            -blur 0x5 -edge 2 -negate -level 75%,100% -blur 0x1
            +level-colors "${BG2},${accent}"
        ')'
        -compose Screen -composite
    )
}

_overlay_orbs() {
    local seed=$1 accent=$2
    RANDOM=$seed
    local cnt=$((3 + RANDOM % 3))
    local i
    for ((i=0; i<cnt; i++)); do
        local color="${ACCENTS[RANDOM % ${#ACCENTS[@]}]}"
        local size=$((400 + RANDOM % 700))
        local x=$((RANDOM % WIDTH - size/2))
        local y=$((RANDOM % HEIGHT - size/2))
        ARGS+=(
            '(' -size "${size}x${size}" "radial-gradient:${color}-none" ')'
            -geometry "+${x}+${y}" -compose Screen -composite
        )
    done
}

_overlay_particles() {
    local seed=$1 accent=$2
    RANDOM=$seed
    local cnt=$((30 + RANDOM % 40))
    local i
    for ((i=0; i<cnt; i++)); do
        local x=$((RANDOM % WIDTH))
        local y=$((RANDOM % HEIGHT))
        local r=$((1 + RANDOM % 3))
        ARGS+=(-fill "$accent" -draw "circle ${x},${y} $((x+r)),${y}")
    done
    ARGS+=(-blur 0x0.8)
}

_overlay_glow() {
    local seed=$1 accent=$2
    RANDOM=$seed
    local size=$((600 + RANDOM % 600))
    local x=$((RANDOM % WIDTH - size/2))
    local y=$((RANDOM % HEIGHT - size/2))
    ARGS+=(
        '(' -size "${size}x${size}" "radial-gradient:${accent}-none" ')'
        -geometry "+${x}+${y}" -compose Screen -composite
        -blur 0x40
    )
}

# ── Theme bases ──
# Args: seed accent dark out [quote]

_gen_marble() {
    local seed=$1 accent=$2 dark=$3 out=$4
    local abstract=$(_pick_abstract "$seed")
    ARGS=(
        -size "${WIDTH}x${HEIGHT}" -seed "$seed" plasma:
        -blur 0x35 -modulate 100,30,100
        +level-colors "${dark},${BG_LIGHT}"
    )
    "_overlay_${abstract}" "$((seed + 7))" "$accent"
    ARGS+=(-modulate 100,75,100 -quality 92 "$out")
    "${IM[@]}" "${ARGS[@]}"
}

_gen_parchment() {
    local seed=$1 accent=$2 dark=$3 out=$4
    local abstract=$(_pick_abstract "$((seed + 1))")
    RANDOM=$seed
    local horizon=$((HEIGHT/2 + (RANDOM % 240 - 120)))
    ARGS=(
        '(' -size "${WIDTH}x${HEIGHT}" "gradient:${dark}-${BG}" ')'
        '('
            -size "${WIDTH}x${HEIGHT}" -seed "$seed" plasma:
            -blur 0x70 -modulate 100,8,100
            +level-colors "${BG2},${BG_LIGHT}"
        ')'
        -compose Overlay -composite
        -fill "$accent" -draw "rectangle 0,$((horizon-1)) ${WIDTH},$((horizon+1))"
        -blur 0x30
    )
    "_overlay_${abstract}" "$((seed + 13))" "$accent"
    ARGS+=(-quality 92 "$out")
    "${IM[@]}" "${ARGS[@]}"
}

_gen_columns() {
    local seed=$1 accent=$2 dark=$3 out=$4
    local abstract=$(_pick_abstract "$((seed + 2))")
    RANDOM=$seed
    local cnt=$((3 + RANDOM % 5))
    local spacing=$((WIDTH / (cnt + 1)))
    ARGS=( -size "${WIDTH}x${HEIGHT}" "gradient:${BG_LIGHT}-${dark}" )
    local i
    for ((i=1; i<=cnt; i++)); do
        local col_w=$((40 + RANDOM % 80))
        local x=$((i * spacing - col_w/2))
        ARGS+=(
            -fill "$dark" -draw "rectangle ${x},0 $((x+col_w)),${HEIGHT}"
            -stroke "$accent" -strokewidth 1
            -draw "line ${x},0 ${x},${HEIGHT}"
            -draw "line $((x+col_w)),0 $((x+col_w)),${HEIGHT}"
            -stroke none
        )
    done
    ARGS+=(-blur 0x2)
    "_overlay_${abstract}" "$((seed + 17))" "$accent"
    ARGS+=(-modulate 100,65,100 -quality 92 "$out")
    "${IM[@]}" "${ARGS[@]}"
}

_gen_memento() {
    local seed=$1 accent=$2 dark=$3 out=$4
    local quote="${5:-}"
    ARGS=(
        -size "${WIDTH}x${HEIGHT}" -seed "$seed" plasma:
        -blur 0x90 -modulate 100,10,100
        +level-colors "${dark},${BG_LIGHT}"
    )
    _overlay_glow "$((seed + 23))" "$accent"
    ARGS+=( -gravity center )
    [ -n "$FONT" ] && ARGS+=( -font "$FONT" )
    # MEMENTO MORI watermark in semi-transparent accent
    ARGS+=( -pointsize 96 -fill "${accent}66" -annotate +0-160 "MEMENTO MORI" )
    # The quote itself, wrapped via caption:
    if [ -n "$quote" ]; then
        ARGS+=(
            '('
                -size 1200x300 -background none -gravity center
                -fill "$FG_DIM"
        )
        [ -n "$FONT" ] && ARGS+=( -font "$FONT" )
        ARGS+=(
                -pointsize 28 "caption:${quote}"
            ')'
            -geometry +0+80 -compose Over -composite
        )
    fi
    ARGS+=( -quality 92 "$out" )
    "${IM[@]}" "${ARGS[@]}"
}

# ── Drivers ──

_render_set() {
    local seed=$1 prefix=$2 quote="${3:-}"
    local i theme accent dark out
    for ((i=0; i<${#THEMES[@]}; i++)); do
        theme="${THEMES[$i]}"
        out="${WALLDIR}/${prefix}-${theme}.png"
        if [ -f "$out" ] && [ -z "${STOA_WALLS_FORCE:-}" ]; then continue; fi
        accent="$(_pick_accent "$((seed + i*5))")"
        dark="$BG2"
        if [ "$theme" = "memento" ]; then
            if "_gen_${theme}" "$((seed + i))" "$accent" "$dark" "$out" "$quote" 2>/dev/null; then
                echo "  [+] $(basename "$out")  (${accent})"
            else
                echo "  [!] failed: ${theme} prefix=${prefix}" >&2
            fi
        else
            if "_gen_${theme}" "$((seed + i))" "$accent" "$dark" "$out" 2>/dev/null; then
                echo "  [+] $(basename "$out")  (${accent})"
            else
                echo "  [!] failed: ${theme} prefix=${prefix}" >&2
            fi
        fi
    done
}

# ── CLI ──

cmd_defaults() {
    mkdir -p "$WALLDIR"
    echo "Generating default wallpapers (one per theme)..."
    STOA_WALLS_FORCE=1
    local i theme accent
    for ((i=0; i<${#THEMES[@]}; i++)); do
        theme="${THEMES[$i]}"
        accent="${ACCENTS[$i]}"
        local out="${WALLDIR}/${theme}.png"
        if [ "$theme" = "memento" ]; then
            _gen_memento $((42 + i)) "$accent" "$BG2" "$out" "Memento mori. — Stoa Linux"
        else
            "_gen_${theme}" $((42 + i)) "$accent" "$BG2" "$out"
        fi
        echo "  [+] ${theme}.png  (${accent})"
    done
    echo "Done. → $WALLDIR"
}

cmd_quotes() {
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

Themes:     ${THEMES[*]}
Abstracts:  ${ABSTRACTS[*]}   (overlay chosen per theme by seed)

Commands:
  defaults          One wallpaper per theme, fixed seed (marble.png,
                    parchment.png, columns.png, memento.png).
                    hyprland.conf hardcodes marble.png — keep this.
  quotes [N]        For each quote in \$QUOTES_FILE, render one
                    wallpaper per theme (4 per quote total). Seeded
                    by SHA1(quote) so it's idempotent.
  regen [N]         clean + quotes.
  clean             Remove generated quote-*.png (keeps defaults).
  help              This text.

Output dir: $WALLDIR
Quotes:     $QUOTES_FILE

No args = defaults + quotes.
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
