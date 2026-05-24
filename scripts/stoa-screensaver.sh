#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Screensaver                                   ║
# ║  "Leisure without study is death." — Seneca                  ║
# ║                                                              ║
# ║  Living marble animation in the Stoic palette.               ║
# ║  Generates organic plasma noise, maps to Stoa colors,        ║
# ║  and plays fullscreen on idle via swayidle.                   ║
# ║                                                              ║
# ║  Requires: imagemagick, ffmpeg, mpv                          ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_SS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/screensaver"
STOA_SS_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/screensaver.conf"
STOA_SS_VIDEO="${STOA_SS_DIR}/marble-flow.mp4"
STOA_SS_LOCK="${XDG_RUNTIME_DIR:-/tmp}/stoa-screensaver-${UID}.lock"

# ── ImageMagick detection ──
# Support both IM7 (`magick`) and IM6 (`convert`). The plasma/CLUT/draw
# syntax used below is identical across both versions.
if command -v magick &>/dev/null; then
    IM=(magick)
elif command -v convert &>/dev/null; then
    IM=(convert)
else
    IM=()
fi

# ── Stoa Palette ──
BG="#211e19"
BG_LIGHT="#2d2921"
BRONZE="#c49a5c"
GOLD="#d4a84b"
OLIVE="#8a9a6c"
TERRACOTTA="#b36b5a"
STONE="#6e6a62"
FG="#d4cfc4"

# ── Config helpers ──

_ss_save() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "$STOA_SS_CONF")"
    [ ! -f "$STOA_SS_CONF" ] && touch "$STOA_SS_CONF"
    if grep -q "^${key}=" "$STOA_SS_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$STOA_SS_CONF"
    else
        echo "${key}=${val}" >> "$STOA_SS_CONF"
    fi
}

_ss_get() {
    local key="$1" default="$2"
    if [ -f "$STOA_SS_CONF" ]; then
        local val
        val=$(grep "^${key}=" "$STOA_SS_CONF" 2>/dev/null | cut -d= -f2)
        [ -n "$val" ] && echo "$val" && return
    fi
    echo "$default"
}

# ── Generation ──

_gen_gradient_clut() {
    local clut_path="${STOA_SS_DIR}/stoa-clut.png"

    "${IM[@]}" -size 1x1 xc:"$BG" xc:"$BG_LIGHT" xc:"$STONE" xc:"$BRONZE" xc:"$GOLD" xc:"$OLIVE" \
        +append -filter Cubic -resize 256x1! \
        "$clut_path"

    echo "$clut_path"
}

_gen_warm_clut() {
    local clut_path="${STOA_SS_DIR}/stoa-clut-warm.png"

    "${IM[@]}" -size 1x1 xc:"$BG" xc:"#1a1714" xc:"$TERRACOTTA" xc:"$BRONZE" xc:"$GOLD" xc:"$FG" \
        +append -filter Cubic -resize 256x1! \
        "$clut_path"

    echo "$clut_path"
}

_gen_cool_clut() {
    local clut_path="${STOA_SS_DIR}/stoa-clut-cool.png"

    "${IM[@]}" -size 1x1 xc:"$BG" xc:"#1a1714" xc:"$STONE" xc:"$OLIVE" xc:"$BRONZE" xc:"$BG_LIGHT" \
        +append -filter Cubic -resize 256x1! \
        "$clut_path"

    echo "$clut_path"
}

generate() {
    local style="${1:-marble}"
    mkdir -p "$STOA_SS_DIR"

    # Dependency check — fail loudly instead of producing an empty video.
    local missing=()
    [ ${#IM[@]} -eq 0 ] && missing+=("imagemagick (magick or convert)")
    command -v ffmpeg &>/dev/null || missing+=("ffmpeg")
    if [ ${#missing[@]} -gt 0 ]; then
        echo "  ERROR: missing dependencies:" >&2
        printf '    - %s\n' "${missing[@]}" >&2
        echo "  Install on Arch: sudo pacman -S imagemagick ffmpeg" >&2
        return 1
    fi

    echo "  Generating Stoa screensaver ($style)..."
    echo ""

    # Frame count + FPS. 1800 frames @ 15fps = 120s — long enough that the
    # mpv loop point is hard to spot, short enough that rendering finishes
    # in a few minutes. Parameters drift continuously (no hard scene cuts)
    # for a slow lava-lamp feel that avoids burn-in.
    local total_frames=1800
    local fps=15

    # Generate small; the heavy blur + final upscale gives an organic look
    # without rendering 1080p plasma per frame.
    local gen_w=240
    local gen_h=135

    local clut_main clut_warm clut_cool
    clut_main=$(_gen_gradient_clut)
    clut_warm=$(_gen_warm_clut)
    clut_cool=$(_gen_cool_clut)
    local cluts=("$clut_main" "$clut_warm" "$clut_cool")

    # Pick a starting CLUT randomly per generation so consecutive runs
    # produce visually different videos. Drift between CLUTs continuously
    # via a Multiply composite later.
    local clut_a="${cluts[RANDOM % 3]}"
    local clut_b="${cluts[RANDOM % 3]}"

    local frame_dir="${STOA_SS_DIR}/frames"
    rm -rf "$frame_dir"
    mkdir -p "$frame_dir"

    local i=0
    local progress=0
    local base_seed=$((RANDOM * 1000))

    while [ $i -lt $total_frames ]; do
        # Continuous drift — no scene cuts. Each frame nudges the seed by
        # a small constant, and blur/sat oscillate via sine-like phases.
        local seed=$((base_seed + i * 5))
        # Three slow oscillators give the lava-lamp feel:
        #   blur 5..11    (period ~ 60 frames = 4s)
        #   sat  60..90   (period ~ 90 frames = 6s)
        #   bri  90..110  (period ~ 120 frames = 8s)
        local blur_sigma=$(( 5 + ((i * 6 / 60) % 7) ))
        local sat=$(( 60 + ((i * 3 / 30) % 31) ))
        local bri=$(( 90 + ((i / 12) % 21) ))

        if ! "${IM[@]}" -size ${gen_w}x${gen_h} -seed "$seed" plasma: \
            -blur 0x${blur_sigma} \
            -modulate "$bri,$sat,100" \
            "$clut_a" -clut \
            -blur 0x2 \
            \( +clone -fill black -colorize 100% \
               -fill white -draw "ellipse $((gen_w/2)),$((gen_h/2)) $((gen_w/2-15)),$((gen_h/2-8)) 0,360" \
               -blur 0x25 \) \
            -compose multiply -composite \
            -resize 1920x1080! \
            -quality 90 \
            "$(printf '%s/frame_%05d.jpg' "$frame_dir" "$i")"; then
            echo "" >&2
            echo "  ERROR: ImageMagick failed rendering frame $i." >&2
            echo "  Check /etc/ImageMagick-*/policy.xml for disabled coders (plasma)." >&2
            rm -rf "$frame_dir"
            return 1
        fi

        # Periodically switch which CLUT we drift through — gradual palette
        # shift over the full duration without abrupt color jumps.
        if (( i > 0 && i % 600 == 0 )); then
            clut_a="$clut_b"
            clut_b="${cluts[RANDOM % 3]}"
        fi

        progress=$(( (i + 1) * 100 / total_frames ))
        printf "\r  Rendering frames... %d%% (%d/%d)" "$progress" "$((i + 1))" "$total_frames"

        i=$((i + 1))
    done

    echo ""
    echo "  Encoding video..."

    # Encode with ffmpeg — high quality, smooth looping.
    # Keep stderr visible so codec/policy issues are diagnosable.
    if ! ffmpeg -y -hide_banner -loglevel error -framerate "$fps" \
        -i "${frame_dir}/frame_%05d.jpg" \
        -c:v libx264 -preset slow -crf 20 \
        -pix_fmt yuv420p \
        -movflags +faststart \
        "$STOA_SS_VIDEO"; then
        echo "  ERROR: ffmpeg failed encoding $STOA_SS_VIDEO" >&2
        rm -rf "$frame_dir"
        return 1
    fi

    # Clean up frames
    rm -rf "$frame_dir"

    # Save style
    _ss_save "STYLE" "$style"

    local duration=$((total_frames / fps))
    echo "  Done! ${duration}s loop → $STOA_SS_VIDEO"
    echo ""
}

# ── Playback ──

start() {
    # Prevent multiple instances
    if [ -f "$STOA_SS_LOCK" ] && kill -0 "$(cat "$STOA_SS_LOCK")" 2>/dev/null; then
        return
    fi

    if ! command -v mpv &>/dev/null; then
        echo "stoa-screensaver: mpv not installed." >&2
        return 1
    fi

    # Generate if not exists
    if [ ! -f "$STOA_SS_VIDEO" ]; then
        if ! generate; then
            return 1
        fi
    fi

    # Dim the screen slightly before starting
    local original_brightness=""
    if command -v brightnessctl &>/dev/null; then
        original_brightness=$(brightnessctl get 2>/dev/null)
    fi

    # Minimal keybindings: any key (or mouse click) exits.
    # We use --input-conf with a tiny generated file rather than disabling
    # bindings entirely (the previous version made the screensaver impossible
    # to dismiss with the keyboard).
    local mpv_conf="${STOA_SS_DIR}/mpv-input.conf"
    cat > "$mpv_conf" <<'EOF'
ANY_UNICODE quit
ESC         quit
ENTER       quit
SPACE       quit
MBTN_LEFT   quit
MBTN_RIGHT  quit
MBTN_MID    quit
EOF

    mpv --fullscreen --loop-file=inf --no-audio \
        --no-config \
        --input-conf="$mpv_conf" \
        --osd-level=0 \
        --no-osc --no-terminal \
        --cursor-autohide=always \
        --force-window=yes \
        --idle=no \
        "$STOA_SS_VIDEO" &
    local mpv_pid=$!
    echo "$mpv_pid" > "$STOA_SS_LOCK"
    wait "$mpv_pid" 2>/dev/null

    rm -f "$STOA_SS_LOCK"

    # Restore brightness
    if [ -n "$original_brightness" ] && command -v brightnessctl &>/dev/null; then
        brightnessctl set "$original_brightness" -q 2>/dev/null
    fi
}

stop() {
    if [ -f "$STOA_SS_LOCK" ]; then
        local pid
        pid=$(cat "$STOA_SS_LOCK")
        kill "$pid" 2>/dev/null
        rm -f "$STOA_SS_LOCK"
    fi
    # Also kill any stray mpv screensaver instances
    pkill -f "mpv.*marble-flow" 2>/dev/null
}

# ── Idle daemon (swayidle integration) ──

enable_idle() {
    local timeout
    timeout=$(_ss_get "IDLE_TIMEOUT" "300")

    # Kill any existing swayidle for screensaver
    pkill -f "swayidle.*stoa-screensaver" 2>/dev/null

    if [ -n "$WAYLAND_DISPLAY" ]; then
        swayidle -w \
            timeout "$timeout" "stoa-screensaver start" \
            resume "stoa-screensaver stop" &
        disown
        _ss_save "ENABLED" "true"
        echo "  Screensaver enabled (${timeout}s idle timeout)"
    else
        # Xorg: use xautolock
        if command -v xautolock &>/dev/null; then
            xautolock -time "$((timeout / 60))" -locker "stoa-screensaver start" &
            disown
            _ss_save "ENABLED" "true"
            echo "  Screensaver enabled (${timeout}s idle timeout)"
        else
            echo "  xautolock not installed for Xorg screensaver"
        fi
    fi
}

disable_idle() {
    pkill -f "swayidle.*stoa-screensaver" 2>/dev/null
    pkill -f "xautolock.*stoa-screensaver" 2>/dev/null
    _ss_save "ENABLED" "false"
    echo "  Screensaver disabled"
}

status() {
    local enabled
    enabled=$(_ss_get "ENABLED" "false")
    local timeout
    timeout=$(_ss_get "IDLE_TIMEOUT" "300")
    local style
    style=$(_ss_get "STYLE" "marble")
    local has_video="no"
    [ -f "$STOA_SS_VIDEO" ] && has_video="yes"

    echo "  Screensaver status:"
    echo "    Enabled:  $enabled"
    echo "    Timeout:  ${timeout}s ($((timeout / 60)) min)"
    echo "    Style:    $style"
    echo "    Video:    $has_video"
    echo "    Running:  $(_is_running)"
}

_is_running() {
    [ -f "$STOA_SS_LOCK" ] && kill -0 "$(cat "$STOA_SS_LOCK")" 2>/dev/null && echo "yes" || echo "no"
}

# ── CLI ──

case "${1:-}" in
    generate)   generate "${2:-marble}" ;;
    start)      start ;;
    stop)       stop ;;
    enable)     enable_idle ;;
    disable)    disable_idle ;;
    status)     status ;;
    set-timeout)
        [ -z "$2" ] && { echo "Usage: stoa-screensaver set-timeout <seconds>"; exit 1; }
        _ss_save "IDLE_TIMEOUT" "$2"
        echo "  Idle timeout: ${2}s"
        # Restart idle watcher if enabled
        [ "$(_ss_get ENABLED false)" = "true" ] && enable_idle
        ;;
    *)
        echo "STOA Screensaver — Living marble animation"
        echo ""
        echo "Usage:"
        echo "  stoa-screensaver generate      Generate animation frames"
        echo "  stoa-screensaver start         Start screensaver now"
        echo "  stoa-screensaver stop          Stop screensaver"
        echo "  stoa-screensaver enable        Enable on idle"
        echo "  stoa-screensaver disable       Disable idle trigger"
        echo "  stoa-screensaver status        Show status"
        echo "  stoa-screensaver set-timeout N Set idle seconds"
        ;;
esac
