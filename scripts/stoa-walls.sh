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
# ║    memento   — soft texture + "memento mori" + week progress  ║
# ║                                                              ║
# ║  Modes:                                                      ║
# ║    defaults — one wallpaper per theme, fixed seed (kept as   ║
# ║               marble.png/parchment.png/columns.png/          ║
# ║               memento.png; Noctalia picks them up from the   ║
# ║               wallpapers directory).                         ║
# ║    quotes   — one wallpaper per theme per quote, seeded by   ║
# ║               SHA1(quote). Idempotent.                       ║
# ║                                                              ║
# ║  Backends (STOA_WALLS_BACKEND, or STOA_WALLS_BACKEND in      ║
# ║  stoa.conf):                                                 ║
# ║    shader — the GLSL renders above (default, offline, fast)  ║
# ║    ai     — local SDXL-Turbo/Lightning through sd-cli (Vulkan)║
# ║             via stoa-walls-ai.py: abstract, varied, with the ║
# ║             quote placed where the image is calmest.         ║
# ║             One-time setup: `stoa-walls setup-ai`.           ║
# ║                                                              ║
# ║  Output: ~/Pictures/Wallpapers (STOA_WALLS_DIR overrides).   ║
# ║                                                              ║
# ║  Requires: glslviewer, imagemagick (memento text only), jq   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ── Config ──
WALLDIR="${STOA_WALLS_DIR:-${HOME}/Pictures/Wallpapers}"
STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
STOA_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
AI_PY="${STOA_DATA}/venv/bin/python"
AI_MODELS="${STOA_DATA}/models"
AI_MODEL_URL="https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors"
AI_MODEL_FILE="sd_xl_turbo_1.0_fp16.safetensors"
AI_MODEL_SIZE=6938081905
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

# ── Backend ──
# Env wins; otherwise a STOA_WALLS_BACKEND= line in stoa.conf; else shader.
if [ -z "${STOA_WALLS_BACKEND:-}" ] && [ -f "$STOA_CONF" ]; then
    STOA_WALLS_BACKEND=$(sed -n 's/^STOA_WALLS_BACKEND=//p' "$STOA_CONF" | tail -n1 | tr -d "\"'[:space:]")
fi
BACKEND="${STOA_WALLS_BACKEND:-shader}"

_ai_script() {
    local self dir
    self=$(readlink -f "${BASH_SOURCE[0]}")
    dir=$(dirname "$self")
    if [ -f "${dir}/stoa-walls-ai.py" ]; then
        echo "${dir}/stoa-walls-ai.py"
    else
        command -v stoa-walls-ai 2>/dev/null
    fi
}

_require_ai() {
    local model="${STOA_WALLS_AI_MODEL:-${AI_MODELS}/${AI_MODEL_FILE}}"
    if ! command -v sd-cli &>/dev/null; then
        echo "stoa-walls: sd-cli not installed. Install: yay -S stable-diffusion.cpp-vulkan-bin" >&2
        exit 1
    fi
    if [ ! -x "$AI_PY" ] || [ ! -f "$model" ]; then
        echo "stoa-walls: AI backend not set up. Run: stoa-walls setup-ai" >&2
        exit 1
    fi
    if [ -z "$(_ai_script)" ]; then
        echo "stoa-walls: stoa-walls-ai.py not found" >&2
        exit 1
    fi
}

_require_backend() {
    case "$BACKEND" in
        ai) _require_ai ;;
        shader) _require_glslviewer ;;
        *) echo "stoa-walls: unknown backend: $BACKEND (use shader or ai)" >&2; exit 2 ;;
    esac
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

# Share of the ISO week elapsed (Mon 00:00 -> Mon 00:00); same formula as
# week_pct in stoa-memento-data.
_week_fraction() {
    local dow secs
    dow=$(date +%u)
    secs=$(( $(date +%s) - $(date -d 'today 00:00:00' +%s) ))
    awk -v d="$dow" -v s="$secs" 'BEGIN { printf "%.4f", ((d - 1) * 86400 + s) / 604800 }'
}

# Composite "memento mori" and a week-progress bar on top of a memento
# wallpaper. Done after the shader because GLSL has no text rendering;
# ImageMagick has good kerning + font fallback.
_overlay_memento_text() {
    local png=$1
    [ ${#IM[@]} -eq 0 ] && return 0
    local font=""
    for f in "EB Garamond" "EB-Garamond" "DejaVu Serif" "serif"; do
        if "${IM[@]}" -list font 2>/dev/null | grep -qiE "^[[:space:]]*(Font:[[:space:]]*)?${f}\$"; then
            font="$f"; break
        fi
    done
    # Bar: 640x8 centred under the title (canvas is WIDTH x HEIGHT).
    local bw=640 bh=8
    local x0=$(( (WIDTH - bw) / 2 )) y0=$(( HEIGHT / 2 + 40 ))
    local fill_x
    fill_x=$(awk -v x="$x0" -v w="$bw" -v f="$(_week_fraction)" 'BEGIN { printf "%d", x + w * f }')
    local args=("$png" -gravity center)
    [ -n "$font" ] && args+=(-font "$font")
    args+=(
        -pointsize 72 -kerning 12 -fill "#c49a5ceb" -annotate +0-20 "memento mori"
        -gravity NorthWest
        -fill "#a89f9145" -draw "roundrectangle ${x0},${y0} $(( x0 + bw )),$(( y0 + bh )) 4,4"
        -fill "#d4a84b"   -draw "roundrectangle ${x0},${y0} ${fill_x},$(( y0 + bh )) 4,4"
        "$png"
    )
    "${IM[@]}" "${args[@]}" 2>/dev/null || true
}

# Render one wallpaper with the active backend. Args: theme seed out [quote]
_render_one() {
    local theme=$1 seed=$2 out=$3 quote="${4:-}"
    if [ "$BACKEND" = "ai" ]; then
        local args=(--theme "$theme" --seed "$seed" --out "$out")
        [ -n "$quote" ] && args+=(--quote "$quote")
        "$AI_PY" -I "$(_ai_script)" "${args[@]}" 2>/dev/null
    else
        _render_shader "$theme" "$seed" "$out" || return 1
        if [ "$theme" = "memento" ]; then
            _overlay_memento_text "$out"
        fi
    fi
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
        if _render_one "$theme" "$theme_seed" "$out" "$quote"; then
            echo "  [+] $(basename "$out")"
        else
            echo "  [!] failed: ${theme} prefix=${prefix}" >&2
        fi
    done
}

# ── CLI ──

cmd_defaults() {
    _require_backend
    mkdir -p "$WALLDIR"
    echo "Generating default wallpapers (one per theme, backend: ${BACKEND})..."
    STOA_WALLS_FORCE=1
    local i theme out
    for ((i=0; i<${#THEMES[@]}; i++)); do
        theme="${THEMES[$i]}"
        out="${WALLDIR}/${theme}.png"
        local seed=$((42 + i * 137))
        if _render_one "$theme" "$seed" "$out" ""; then
            echo "  [+] ${theme}.png"
        else
            echo "  [!] failed: ${theme}" >&2
        fi
    done
    echo "Done. → $WALLDIR"
}

cmd_quotes() {
    _require_backend
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
    # ~14 s per image, 4 per quote: rendering the whole bank with the ai
    # backend takes hours, so cap the default. `quotes N` still overrides.
    if [ "$BACKEND" = "ai" ] && [ "$limit" -eq 0 ]; then
        limit="${STOA_WALLS_AI_LIMIT:-12}"
        echo "ai backend: rendering the first ${limit} quotes (use 'stoa-walls quotes N' for more)."
    fi
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

# Redraw the week-progress bar on the AI memento wallpapers from their saved
# base image (no model run, ~1 s each). Needs only the venv, not sd-cli.
cmd_refresh_memento() {
    local apply=0
    [ "${1:-}" = "--apply" ] && apply=1
    if [ ! -x "$AI_PY" ] || [ -z "$(_ai_script)" ]; then
        echo "stoa-walls: AI backend not set up. Run: stoa-walls setup-ai" >&2
        exit 1
    fi
    [ -d "$WALLDIR" ] || { echo "stoa-walls: no wallpapers in $WALLDIR" >&2; exit 1; }
    local f n=0
    while IFS= read -r f; do
        if "$AI_PY" -I "$(_ai_script)" --refresh --out "$f" 2>/dev/null; then
            echo "  [+] $(basename "$f")"
            n=$((n + 1))
        fi
    done < <(find "$WALLDIR" -maxdepth 1 -type f \( -name 'memento.png' -o -name 'quote-*-memento.png' \) | sort)
    echo "Refreshed ${n} memento wallpaper(s)."
    # Noctalia keeps the decoded image; if memento.png is the wallpaper on
    # screen right now, set it again so the new bar shows. Never switch to
    # it from some other wallpaper — that is `boot`'s job, once per login.
    if [ "$apply" -eq 1 ] && command -v noctalia &>/dev/null; then
        local current
        current=$(noctalia msg wallpaper-get 2>/dev/null)
        if [ -n "$current" ] && [ "$(readlink -f "$current")" = "$(readlink -f "${WALLDIR}/memento.png")" ]; then
            noctalia msg wallpaper-set "${WALLDIR}/memento.png" >/dev/null 2>&1
        fi
    fi
}

# Run once per login, from the compositor autostart: wait for the shell,
# bring the memento bar up to date, and make memento the first wallpaper.
cmd_boot() {
    local memento="${WALLDIR}/memento.png" i
    [ -f "$memento" ] || return 0
    command -v noctalia &>/dev/null || return 0
    if [ -x "$AI_PY" ] && [ -n "$(_ai_script)" ]; then
        "$AI_PY" -I "$(_ai_script)" --refresh --out "$memento" 2>/dev/null || true
    fi
    # No fixed sleep: poll until Noctalia answers (up to ~60 s).
    for i in $(seq 1 60); do
        noctalia msg wallpaper-get &>/dev/null && break
        sleep 1
    done
    noctalia msg wallpaper-set "$memento" >/dev/null 2>&1
}

# One-time setup for the AI backend: Python venv (numpy + Pillow) and the
# SDXL-Turbo checkpoint. Resumable: re-run after an interrupted download.
cmd_setup_ai() {
    command -v uv &>/dev/null || { echo "stoa-walls: uv required. Install: sudo pacman -S uv" >&2; exit 1; }
    if ! command -v sd-cli &>/dev/null; then
        echo "stoa-walls: sd-cli missing. Install: yay -S stable-diffusion.cpp-vulkan-bin" >&2
        exit 1
    fi
    mkdir -p "$AI_MODELS"
    if [ ! -x "$AI_PY" ]; then
        echo "Creating venv in ${STOA_DATA}/venv ..."
        uv venv -q "${STOA_DATA}/venv"
    fi
    uv pip install -q --python "$AI_PY" numpy pillow
    local dest="${AI_MODELS}/${AI_MODEL_FILE}" i
    if [ "$(stat -c %s "$dest" 2>/dev/null)" = "$AI_MODEL_SIZE" ]; then
        echo "Model already downloaded: $dest"
        echo "Done. Enable with: STOA_WALLS_BACKEND=ai stoa-walls   (or set it in stoa.conf)"
        return 0
    fi
    echo "Downloading ${AI_MODEL_FILE} (~6.9 GB, resumable) ..."
    for i in 1 2 3 4 5; do
        # HTTP/1.1: huggingface's HTTP/2 stream sometimes resets mid-file.
        curl -fL --http1.1 -C - -o "$dest" "$AI_MODEL_URL" && break
        echo "  retry ${i}/5" >&2
        sleep 3
    done
    [ -f "$dest" ] || { echo "stoa-walls: download failed" >&2; exit 1; }
    echo "Done. Enable with: STOA_WALLS_BACKEND=ai stoa-walls   (or set it in stoa.conf)"
}

cmd_help() {
    cat <<EOF
Usage: stoa-walls <command> [args]

Backend:   ${BACKEND}  (STOA_WALLS_BACKEND=shader|ai)
Themes:    ${THEMES[*]}
Shaders:   $SHADER_DIR
Output:    $WALLDIR
Quotes:    $QUOTES_FILE

Commands:
  defaults          One wallpaper per theme, fixed seed (marble.png,
                    parchment.png, columns.png, memento.png).
                    Noctalia owns setting/rotating the wallpaper.
  quotes [N]        Render one wallpaper per theme per quote, seeded
                    by SHA1(quote). Optional N caps how many quotes
                    (ai backend defaults to 12: ~1 min per quote).
  regen [N]         clean + quotes.
  clean             Remove generated quote-*.png (keeps defaults).
  refresh-memento [--apply]
                    Redraw the week bar on the ai memento wallpapers
                    (no model run). --apply also re-sets memento.png if it
                    is the wallpaper on screen. A systemd user timer runs
                    this daily at 00:05.
  boot              Run at login: refresh the bar and set memento.png as
                    the wallpaper (started by the compositor autostart).
  setup-ai          One-time: venv + SDXL-Turbo model for the ai backend.
  help              This text.

No args = defaults + quotes.

Requires: glslviewer (AUR), imagemagick, jq.
AI backend: sd-cli (yay -S stable-diffusion.cpp-vulkan-bin), uv.

RESUMO RÁPIDO
  stoa-walls
  stoa-walls defaults
  stoa-walls quotes [N]
  stoa-walls regen [N]
  stoa-walls clean
  stoa-walls setup-ai
  stoa-walls refresh-memento [--apply]
  stoa-walls boot
  STOA_WALLS_BACKEND=ai stoa-walls
  stoa-walls help | -h | --help
EOF
}

case "${1:-}" in
    defaults) shift; cmd_defaults "$@" ;;
    quotes)   shift; cmd_quotes "$@" ;;
    regen)    shift; cmd_regen "$@" ;;
    clean)    shift; cmd_clean "$@" ;;
    setup-ai) shift; cmd_setup_ai "$@" ;;
    refresh-memento) shift; cmd_refresh_memento "$@" ;;
    boot)     shift; cmd_boot "$@" ;;
    help|--help|-h) cmd_help ;;
    "")       cmd_defaults; echo; cmd_quotes ;;
    *)        echo "stoa-walls: unknown command: $1" >&2; cmd_help >&2; exit 2 ;;
esac
