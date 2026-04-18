#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Quotes                                        ║
# ║  "Wealth consists not in having great possessions, but in   ║
# ║   having few wants." — Epictetus                             ║
# ║                                                              ║
# ║  Bank:      ~/.local/share/stoa/quotes.json                  ║
# ║  Playlist:  ~/.local/share/stoa/playlist (shuffled queue)    ║
# ║  Each app consumes the next quote via "next".                ║
# ║  Sync: on boot + when the playlist runs out.                 ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
QUOTES_FILE="$STOA_DIR/quotes.json"
PLAYLIST_FILE="$STOA_DIR/playlist"
BOOT_ID_FILE="$STOA_DIR/.boot-id"
SYNC_LOCK="$STOA_DIR/.sync.lock"
PLAYLIST_LOCK="$STOA_DIR/.playlist.lock"

FETCH_COUNT=75
FALLBACK="The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius"

# ── Colors ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Built-in quotes (initial seed) ──
_builtin_quotes() {
    cat <<'EOF'
[
  "The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius",
  "We suffer more often in imagination than in reality. — Seneca",
  "It's not what happens to you, but how you react to it that matters. — Epictetus",
  "Wealth consists not in having great possessions, but in having few wants. — Epictetus",
  "The impediment to action advances action. What stands in the way becomes the way. — Marcus Aurelius",
  "We have two ears and one mouth so that we can listen twice as much as we speak. — Zeno of Citium",
  "Virtue is the sole good. — Zeno of Citium",
  "Luck is what happens when preparation meets opportunity. — Seneca",
  "If you want to improve, be content to be thought foolish and stupid. — Epictetus",
  "The soul becomes dyed with the colour of its thoughts. — Marcus Aurelius",
  "No man is free who is not master of himself. — Epictetus",
  "Begin at once to live, and count each separate day as a separate life. — Seneca",
  "He who fears death will never do anything worthy of a living man. — Seneca",
  "First say to yourself what you would be; and then do what you have to do. — Epictetus",
  "You have power over your mind, not outside events. Realize this, and you will find strength. — Marcus Aurelius",
  "It is not that we have a short time to live, but that we waste a great deal of it. — Seneca",
  "Man is not worried by real problems so much as by his imagined anxieties about real problems. — Epictetus",
  "The best revenge is not to be like your enemy. — Marcus Aurelius",
  "Difficulties strengthen the mind, as labor does the body. — Seneca",
  "How long are you going to wait before you demand the best for yourself? — Epictetus",
  "Waste no more time arguing about what a good man should be. Be one. — Marcus Aurelius",
  "Associate with people who are likely to improve you. — Seneca",
  "Freedom is the only worthy goal in life. It is won by disregarding things that lie beyond our control. — Epictetus",
  "Memento Mori — Remember that you will die.",
  "Amor Fati — Love your fate.",
  "Order is the first law of heaven. — Marcus Aurelius",
  "Endure and renounce. — Epictetus",
  "Action is the mark of wisdom. — Seneca",
  "The path of the wise is prepared. — Seneca",
  "Adapt yourself to the things among which your lot has been cast. — Marcus Aurelius"
]
EOF
}

# ── Initialize ──
_init() {
    mkdir -p "$STOA_DIR"
    [ -f "$QUOTES_FILE" ] || _builtin_quotes > "$QUOTES_FILE"
}

# ── APIs ──
_fetch_one() {
    local r q a
    r=$(curl -sf --max-time 5 "https://stoic.tekloon.net/stoic-quote" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$r" ]; then
        q=$(printf '%s' "$r" | jq -r '.data.quote // empty' 2>/dev/null)
        a=$(printf '%s' "$r" | jq -r '.data.author // empty' 2>/dev/null)
        [ -n "$q" ] && echo "${q} — ${a}" && return 0
    fi
    r=$(curl -sf --max-time 5 "https://api.stoicquotesapi.com/v1/api/quotes/random" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$r" ]; then
        q=$(printf '%s' "$r" | jq -r '.body // .quote // empty' 2>/dev/null)
        a=$(printf '%s' "$r" | jq -r '.author // empty' 2>/dev/null)
        [ -n "$q" ] && echo "${q} — ${a}" && return 0
    fi
    return 1
}

_add_quote() {
    local q="$1"
    if jq -e --arg q "$q" 'map(ascii_downcase == ($q | ascii_downcase)) | any' "$QUOTES_FILE" &>/dev/null; then
        return 1
    fi
    local tmp
    tmp=$(jq --arg q "$q" '. + [$q]' "$QUOTES_FILE") && echo "$tmp" > "$QUOTES_FILE"
}

# ── Sync: fetch new quotes ──
_do_sync() {
    local interactive="${1:-false}"
    _init
    command -v curl &>/dev/null && command -v jq &>/dev/null || return 1

    if [ -f "$SYNC_LOCK" ]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$SYNC_LOCK" 2>/dev/null || echo 0) ))
        [ "$age" -gt 300 ] && rm -f "$SYNC_LOCK" || return 0
    fi
    touch "$SYNC_LOCK"

    local added=0 tried=0
    for i in $(seq 1 "$FETCH_COUNT"); do
        local quote=""
        quote=$(_fetch_one) || true
        if [ -n "$quote" ]; then
            tried=$((tried + 1))
            if _add_quote "$quote"; then
                added=$((added + 1))
                [ "$interactive" = "true" ] && echo -e "  ${O}[+]${R} ${quote}"
            else
                [ "$interactive" = "true" ] && echo -e "  ${S}[~]${R} (duplicate)"
            fi
        else
            [ "$interactive" = "true" ] && echo -e "  ${T}[!]${R} Failed #$i"
        fi
        [ "$i" -lt "$FETCH_COUNT" ] && sleep 0.3
    done

    rm -f "$SYNC_LOCK"

    if [ "$interactive" = "true" ]; then
        local total
        total=$(jq 'length' "$QUOTES_FILE")
        echo ""
        echo -e "  ${B}Results:${R}"
        echo -e "  ${S}  Fetched:  ${tried}${R}"
        echo -e "  ${S}  New:      ${added}${R}"
        echo -e "  ${S}  Total:    ${total} quotes${R}"
        echo -e "  ${S}  File:     ${QUOTES_FILE}${R}"
        echo ""
    fi
}

# ── Playlist: shuffle indices ──
_rebuild_playlist() {
    _init
    local total
    total=$(jq 'length' "$QUOTES_FILE" 2>/dev/null || echo 0)
    [ "$total" -eq 0 ] && return
    seq 0 $((total - 1)) | shuf > "$PLAYLIST_FILE"
}

# ── Detect new boot ──
_is_new_boot() {
    local current_boot
    current_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")
    if [ ! -f "$BOOT_ID_FILE" ]; then
        echo "$current_boot" > "$BOOT_ID_FILE"
        return 0
    fi
    local saved_boot
    saved_boot=$(cat "$BOOT_ID_FILE" 2>/dev/null)
    if [ "$current_boot" != "$saved_boot" ]; then
        echo "$current_boot" > "$BOOT_ID_FILE"
        return 0
    fi
    return 1
}

# ── Next: consume the next quote from the playlist ──
# Each call returns a different quote.
# Auto sync on boot and when the playlist runs out.
_cmd_next() {
    _init

    # New boot? Sync in background + reshuffle
    if _is_new_boot; then
        _rebuild_playlist
        ( _do_sync false && _rebuild_playlist ) &
        disown 2>/dev/null
    fi

    # No playlist? Create one
    [ -f "$PLAYLIST_FILE" ] || _rebuild_playlist

    # Lock for atomic playlist access (prevents 2 apps from getting the same quote)
    local result
    result=$(
        (
            flock -w 2 200 || exit 1

            # Empty playlist? All consumed → sync + rebuild
            if [ ! -s "$PLAYLIST_FILE" ]; then
                _rebuild_playlist
                ( _do_sync false && _rebuild_playlist ) &
                disown 2>/dev/null
            fi

            # Pop first index
            local idx
            idx=$(head -1 "$PLAYLIST_FILE" 2>/dev/null)
            sed -i '1d' "$PLAYLIST_FILE"

            [ -n "$idx" ] && jq -r ".[$idx] // empty" "$QUOTES_FILE" 2>/dev/null
        ) 200>"$PLAYLIST_LOCK"
    )

    echo "${result:-$FALLBACK}"
}

_cmd_count() { _init; jq 'length' "$QUOTES_FILE"; }
_cmd_list()  { _init; jq -r 'to_entries[] | "\(.key + 1). \(.value)"' "$QUOTES_FILE"; }
_cmd_remaining() { _init; [ -f "$PLAYLIST_FILE" ] && wc -l < "$PLAYLIST_FILE" || echo 0; }

_cmd_add() {
    local quote="$1"
    [ -z "$quote" ] && { echo -e "  ${T}Usage: stoa-quotes-sync add \"Quote — Author\"${R}"; return 1; }
    _init
    if _add_quote "$quote"; then
        echo -e "  ${O}[+] Added: ${quote}${R}"
    else
        echo -e "  ${S}[~] Already exists: ${quote}${R}"
    fi
}

_cmd_reset() {
    rm -f "$QUOTES_FILE" "$PLAYLIST_FILE" "$BOOT_ID_FILE"
    _init
    _rebuild_playlist
    echo -e "  ${O}[✓] Reset to $(jq 'length' "$QUOTES_FILE") built-in quotes.${R}"
}

_cmd_sync() {
    command -v curl &>/dev/null || { echo -e "  ${T}[!] curl not found.${R}"; exit 1; }
    command -v jq &>/dev/null   || { echo -e "  ${T}[!] jq not found.${R}"; exit 1; }
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA QUOTES — Fetching wisdom...                 ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    _do_sync true
    _rebuild_playlist
    echo -e "  ${O}[✓] Playlist reshuffled ($(wc -l < "$PLAYLIST_FILE") quotes).${R}"
    echo ""
}

_cmd_help() {
    echo ""
    echo -e "  ${B}stoa-quotes-sync${R} — Stoic quotes"
    echo ""
    echo -e "  ${S}Bank:      ${QUOTES_FILE}${R}"
    echo -e "  ${S}Playlist:  ${PLAYLIST_FILE}${R}"
    echo ""
    echo -e "  ${S}Each app gets a different quote via \"next\".${R}"
    echo -e "  ${S}Auto sync on boot and when the playlist runs out.${R}"
    echo ""
    echo -e "  ${S}Commands:${R}"
    echo -e "    ${O}stoa-quotes-sync${R}             Fetch quotes now"
    echo -e "    ${O}stoa-quotes-sync next${R}        Next quote (consumes from playlist)"
    echo -e "    ${O}stoa-quotes-sync remaining${R}   Remaining quotes in playlist"
    echo -e "    ${O}stoa-quotes-sync list${R}        List all from bank"
    echo -e "    ${O}stoa-quotes-sync count${R}       Total in bank"
    echo -e "    ${O}stoa-quotes-sync add \"...\"${R}   Add quote manually"
    echo -e "    ${O}stoa-quotes-sync reset${R}       Reset to built-in quotes"
    echo ""
}

# ── Main ──
case "${1:-}" in
    next|random|tick) _cmd_next ;;
    remaining)        _cmd_remaining ;;
    count)            _cmd_count ;;
    list)             _cmd_list ;;
    add)              shift; _cmd_add "$*" ;;
    reset)            _cmd_reset ;;
    help|-h|--help)   _cmd_help ;;
    *)                _cmd_sync ;;
esac
