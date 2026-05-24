#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Wallpaper Generator                           ║
# ║  Generates abstract wallpapers in the Stoic palette.        ║
# ║                                                              ║
# ║  Two modes:                                                  ║
# ║    classic  — the 4 minimalist wallpapers (marble, etc.)    ║
# ║    quotes   — one batch of 4 per quote in quotes.json,      ║
# ║               seeded by SHA1(quote) so a given quote always  ║
# ║               yields the same 4 images. Drop hundreds of    ║
# ║               wallpapers in $WALLDIR for Noctalia rotation.  ║
# ║                                                              ║
# ║  Requires: imagemagick, jq                                   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ── Config ──
WALLDIR="${HOME}/.config/stoa/wallpapers"
QUOTES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/quotes.json"
WIDTH=1920
HEIGHT=1080
PER_QUOTE=4

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

ACCENTS=("$BRONZE" "$GOLD" "$OLIVE" "$TERRACOTTA" "$STONE")
DARKS=("$BG" "$BG2" "$BG_LIGHT")
GENERATORS=(plasma_marble plasma_veins orbs horizon mosaic constellation)

# ── ImageMagick detection ──
if command -v magick &>/dev/null; then IM=(magick)
elif command -v convert &>/dev/null; then IM=(convert)
else
    echo "stoa-walls: ImageMagick not found. Install: sudo pacman -S imagemagick" >&2
    exit 1
fi

_pick_font() {
    local candidates=("EB Garamond" "EB-Garamond" "JetBrains Mono" "DejaVu Serif" "serif")
    for f in "${candidates[@]}"; do
        if "${IM[@]}" -list font 2>/dev/null | grep -qiE "^[[:space:]]*(Font:[[:space:]]*)?${f}\$"; then
            echo "$f"; return
        fi
    done
    echo ""
}
FONT=$(_pick_font)

# ── Helpers ──

# SHA1(text) → first 8 hex chars
_hash8() { printf '%s' "$1" | sha1sum | head -c 8; }

# First 8 hex of $1 as a decimal int (clamped to 2^31)
_seed_from_hash() {
    local h="$1"
    printf '%d' "0x$h" | awk '{print ($1<0?-$1:$1) % 2147483647}'
}

# ── Generators ──
# Each generator takes:  $1=seed (int)  $2=accent  $3=dark  $4=out_path

_gen_plasma_marble() {
    local seed=$1 accent=$2 dark=$3 out=$4
    "${IM[@]}" -size ${WIDTH}x${HEIGHT} -seed "$seed" plasma: \
        -blur 0x25 \
        -modulate 100,55,100 \
        +level-colors "$dark","$accent" \
        -modulate 100,70,100 \
        -quality 92 \
        "$out"
}

_gen_plasma_veins() {
    local seed=$1 accent=$2 dark=$3 out=$4
    "${IM[@]}" -size ${WIDTH}x${HEIGHT} -seed "$seed" plasma: \
        -blur 0x6 \
        -edge 2 \
        -negate \
        -level 60%,100% \
        -blur 0x1.5 \
        +level-colors "$dark","$accent" \
        -modulate 100,55,100 \
        -quality 92 \
        "$out"
}

_gen_orbs() {
    local seed=$1 accent=$2 dark=$3 out=$4
    RANDOM=$seed
    local args=(-size ${WIDTH}x${HEIGHT} canvas:"$dark")
    local cnt=$((4 + RANDOM % 4))   # 4-7 orbs
    local i color size x y
    for ((i=0; i<cnt; i++)); do
        # Alternate accent + a second accent for variety
        if (( RANDOM % 3 == 0 )); then
            color="${ACCENTS[RANDOM % ${#ACCENTS[@]}]}"
        else
            color="$accent"
        fi
        size=$((500 + RANDOM % 900))
        x=$((RANDOM % WIDTH - size/2))
        y=$((RANDOM % HEIGHT - size/2))
        args+=(
            \( -size ${size}x${size} radial-gradient:"${color}"-none \)
            -geometry "+${x}+${y}" -compose Screen -composite
        )
    done
    args+=(-blur 0x35 -modulate 100,75,100 -quality 92 "$out")
    "${IM[@]}" "${args[@]}"
}

_gen_horizon() {
    local seed=$1 accent=$2 dark=$3 out=$4
    RANDOM=$seed
    local horizon=$(( HEIGHT/2 + (RANDOM % 200 - 100) ))   # 440-640
    local sky2="${ACCENTS[RANDOM % ${#ACCENTS[@]}]}"
    "${IM[@]}" \
        \( -size ${WIDTH}x${horizon} gradient:"$dark"-"$sky2" \) \
        \( -size ${WIDTH}x$((HEIGHT - horizon)) gradient:"$accent"-"$BG2" \) \
        -append \
        -blur 0x2 \
        -modulate 100,60,100 \
        -fill "$FG_DIM" -draw "line 0,${horizon} ${WIDTH},${horizon}" \
        -blur 0x1 \
        -quality 92 \
        "$out"
}

_gen_mosaic() {
    local seed=$1 accent=$2 dark=$3 out=$4
    RANDOM=$seed
    # Generate a small canvas of random palette tiles, blur+scale for organic look.
    local tw=12 th=7
    local tile_args=(-size $((WIDTH/tw))x$((HEIGHT/th)) canvas:"$dark")
    local i j color
    "${IM[@]}" -size ${tw}x${th} canvas:"$dark" -depth 8 "/tmp/stoa-walls-mosaic-$$.miff"
    # Build a tw×th grid via pixel draw — cheaper than spawning IM many times.
    local seed_args=()
    for ((j=0; j<th; j++)); do
        for ((i=0; i<tw; i++)); do
            if (( RANDOM % 4 == 0 )); then
                color="${ACCENTS[RANDOM % ${#ACCENTS[@]}]}"
            else
                color="${DARKS[RANDOM % ${#DARKS[@]}]}"
            fi
            seed_args+=(-fill "$color" -draw "point ${i},${j}")
        done
    done
    "${IM[@]}" -size ${tw}x${th} canvas:"$dark" \
        "${seed_args[@]}" \
        -filter Cubic -resize ${WIDTH}x${HEIGHT}^ \
        -gravity center -crop ${WIDTH}x${HEIGHT}+0+0 +repage \
        -blur 0x30 \
        -modulate 100,80,100 \
        -quality 92 \
        "$out"
    rm -f "/tmp/stoa-walls-mosaic-$$.miff"
}

_gen_constellation() {
    local seed=$1 accent=$2 dark=$3 out=$4
    RANDOM=$seed
    # Background: subtle plasma in dark tones
    local bg_seed=$((seed + 7919))
    local args=(-size ${WIDTH}x${HEIGHT} -seed "$bg_seed" plasma:
                -blur 0x40 -modulate 100,15,100
                +level-colors "$BG2","$BG_LIGHT")
    # Random stars (small bright circles)
    local cnt=$((40 + RANDOM % 40))
    local i x y r
    local prev_x prev_y
    for ((i=0; i<cnt; i++)); do
        x=$((RANDOM % WIDTH))
        y=$((RANDOM % HEIGHT))
        r=$((1 + RANDOM % 3))
        args+=(-fill "$accent" -draw "circle ${x},${y} $((x+r)),${y}")
        # Occasional thin connecting line to previous star
        if (( i > 0 && RANDOM % 5 == 0 )); then
            args+=(-stroke "$accent" -strokewidth 1
                   -draw "line ${prev_x},${prev_y} ${x},${y}"
                   -stroke none)
        fi
        prev_x=$x
        prev_y=$y
    done
    args+=(-blur 0x0.5 -quality 92 "$out")
    "${IM[@]}" "${args[@]}"
}

# ── Per-quote driver ──

_pick_gens() {
    # Deterministically pick PER_QUOTE distinct generators from $GENERATORS,
    # seeded by hash. Echoes one gen name per line.
    local seed=$1
    RANDOM=$seed
    local picked=()
    local available=("${GENERATORS[@]}")
    local i idx
    for ((i=0; i<PER_QUOTE && ${#available[@]} > 0; i++)); do
        idx=$((RANDOM % ${#available[@]}))
        picked+=("${available[$idx]}")
        unset 'available[idx]'
        available=("${available[@]}")
    done
    printf '%s\n' "${picked[@]}"
}

_render_for_quote() {
    local quote="$1"
    local hash=$(_hash8 "$quote")
    local base_seed=$(_seed_from_hash "$hash")

    mapfile -t gens < <(_pick_gens "$base_seed")
    local i
    for ((i=0; i<${#gens[@]}; i++)); do
        local gen="${gens[$i]}"
        local out="$WALLDIR/quote-${hash}-${gen}.png"
        if [ -f "$out" ]; then continue; fi
        # Different sub-seed per generator so they don't share noise.
        local sub_seed=$((base_seed + i * 1013))
        local accent="${ACCENTS[$(( (base_seed + i*3) % ${#ACCENTS[@]} ))]}"
        local dark="${DARKS[$(( (base_seed + i) % ${#DARKS[@]} ))]}"
        if "_gen_${gen}" "$sub_seed" "$accent" "$dark" "$out" 2>/dev/null; then
            echo "  [+] quote-${hash}-${gen}.png  (${gen}, ${accent})"
        else
            echo "  [!] failed: $gen for ${hash}" >&2
        fi
    done
}

# ── Classic 4 ──
# Kept for backward compat (hyprland.conf hardcodes marble.png).

_render_classic() {
    "${IM[@]}" -size ${WIDTH}x${HEIGHT} -seed 42 plasma: \
        -blur 0x40 -modulate 100,30,100 \
        +level-colors "$BG2","$BG_LIGHT" \
        "$WALLDIR/marble.png"
    echo "  [+] marble.png"

    "${IM[@]}" -size ${WIDTH}x${HEIGHT} \
        gradient:"$BG"-"$BG2" \
        -fill "$BRONZE" -draw "rectangle 0,$((HEIGHT/2-1)),${WIDTH},$((HEIGHT/2+1))" \
        -blur 0x35 \
        "$WALLDIR/parchment.png"
    echo "  [+] parchment.png"

    "${IM[@]}" -size ${WIDTH}x${HEIGHT} canvas:"$BG2" \
        -fill "$BG_LIGHT" \
        -draw "rectangle $((WIDTH/2-60)),0,$((WIDTH/2-58)),${HEIGHT}" \
        -draw "rectangle $((WIDTH/2-30)),0,$((WIDTH/2-28)),${HEIGHT}" \
        -draw "rectangle $((WIDTH/2)),0,$((WIDTH/2+2)),${HEIGHT}" \
        -draw "rectangle $((WIDTH/2+30)),0,$((WIDTH/2+32)),${HEIGHT}" \
        -draw "rectangle $((WIDTH/2+60)),0,$((WIDTH/2+62)),${HEIGHT}" \
        "$WALLDIR/columns.png"
    echo "  [+] columns.png"

    local memento_args=(-size ${WIDTH}x${HEIGHT} canvas:"$BG2" -gravity center)
    [ -n "$FONT" ] && memento_args+=(-font "$FONT")
    memento_args+=(-pointsize 64 -fill "$STONE" -annotate +0+0 "MEMENTO MORI" "$WALLDIR/memento.png")
    "${IM[@]}" "${memento_args[@]}"
    echo "  [+] memento.png"
}

# ── CLI ──

cmd_classic() {
    mkdir -p "$WALLDIR"
    echo "Generating classic wallpapers..."
    _render_classic
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
    echo "Generating wallpapers from $total quotes (${PER_QUOTE} per quote)..."
    while IFS= read -r quote; do
        [ -z "$quote" ] && continue
        _render_for_quote "$quote"
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

Commands:
  classic           Generate the 4 minimalist wallpapers (marble, parchment,
                    columns, memento). Required for stoa-greeter compat.
  quotes [N]        Generate ${PER_QUOTE} abstract wallpapers per quote in
                    \$QUOTES_FILE. Optional N limits the number of quotes.
  regen [N]         clean + quotes.
  clean             Remove the generated quote-*.png files (keeps classics).
  help              This text.

Output dir: $WALLDIR
Quotes:     $QUOTES_FILE
Generators: ${GENERATORS[*]}

Default (no args): classic + quotes.
EOF
}

case "${1:-}" in
    classic) shift; cmd_classic "$@" ;;
    quotes)  shift; cmd_quotes "$@" ;;
    regen)   shift; cmd_regen "$@" ;;
    clean)   shift; cmd_clean "$@" ;;
    help|--help|-h) cmd_help ;;
    "")      cmd_classic; echo; cmd_quotes ;;
    *)       echo "stoa-walls: unknown command: $1" >&2; cmd_help >&2; exit 2 ;;
esac
