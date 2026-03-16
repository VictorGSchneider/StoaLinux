#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Quotes                                        ║
# ║  "A riqueza consiste não em ter grandes posses, mas em ter  ║
# ║   poucas necessidades." — Epicteto                          ║
# ║                                                              ║
# ║  Banco:     ~/.local/share/stoa/quotes.json                  ║
# ║  Playlist:  ~/.local/share/stoa/playlist (fila embaralhada)  ║
# ║  Cada app consome a próxima frase via "next".                ║
# ║  Sync: no boot + quando a playlist esvazia.                  ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
QUOTES_FILE="$STOA_DIR/quotes.json"
PLAYLIST_FILE="$STOA_DIR/playlist"
BOOT_ID_FILE="$STOA_DIR/.boot-id"
SYNC_LOCK="$STOA_DIR/.sync.lock"
PLAYLIST_LOCK="$STOA_DIR/.playlist.lock"

FETCH_COUNT=75
FALLBACK="The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius"

# ── Cores ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Frases embutidas (seed inicial) ──
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
  "A felicidade depende da qualidade dos teus pensamentos. — Marco Aurélio",
  "Não sofras antes do tempo. — Sêneca",
  "Não é o que te acontece, mas como reages ao que te acontece. — Epicteto",
  "O impedimento à ação avança a ação. O que se interpõe no caminho torna-se o caminho. — Marco Aurélio",
  "A virtude é o único bem. — Zenão de Cítio"
]
EOF
}

# ── Inicializar ──
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

# ── Sync: busca frases novas ──
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
                [ "$interactive" = "true" ] && echo -e "  ${S}[~]${R} (duplicada)"
            fi
        else
            [ "$interactive" = "true" ] && echo -e "  ${T}[!]${R} Falha #$i"
        fi
        [ "$i" -lt "$FETCH_COUNT" ] && sleep 0.3
    done

    rm -f "$SYNC_LOCK"

    if [ "$interactive" = "true" ]; then
        local total
        total=$(jq 'length' "$QUOTES_FILE")
        echo ""
        echo -e "  ${B}Resultado:${R}"
        echo -e "  ${S}  Buscadas:  ${tried}${R}"
        echo -e "  ${S}  Novas:     ${added}${R}"
        echo -e "  ${S}  Total:     ${total} frases${R}"
        echo -e "  ${S}  Arquivo:   ${QUOTES_FILE}${R}"
        echo ""
    fi
}

# ── Playlist: embaralha índices ──
_rebuild_playlist() {
    _init
    local total
    total=$(jq 'length' "$QUOTES_FILE" 2>/dev/null || echo 0)
    [ "$total" -eq 0 ] && return
    seq 0 $((total - 1)) | shuf > "$PLAYLIST_FILE"
}

# ── Detectar boot novo ──
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

# ── Next: consome a próxima frase da playlist ──
# Cada chamada retorna uma frase diferente.
# Sync automático no boot e quando a playlist esvazia.
_cmd_next() {
    _init

    # Boot novo? Sync em background + reembaralhar
    if _is_new_boot; then
        _rebuild_playlist
        ( _do_sync false && _rebuild_playlist ) &
        disown 2>/dev/null
    fi

    # Sem playlist? Criar
    [ -f "$PLAYLIST_FILE" ] || _rebuild_playlist

    # Lock para acesso atômico à playlist (evita 2 apps pegarem a mesma frase)
    local result
    result=$(
        (
            flock -w 2 200 || exit 1

            # Playlist vazia? Todas consumidas → sync + rebuild
            if [ ! -s "$PLAYLIST_FILE" ]; then
                _rebuild_playlist
                ( _do_sync false && _rebuild_playlist ) &
                disown 2>/dev/null
            fi

            # Pop primeiro índice
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
    [ -z "$quote" ] && { echo -e "  ${T}Uso: stoa-quotes-sync add \"Quote — Author\"${R}"; return 1; }
    _init
    if _add_quote "$quote"; then
        echo -e "  ${O}[+] Adicionada: ${quote}${R}"
    else
        echo -e "  ${S}[~] Já existe: ${quote}${R}"
    fi
}

_cmd_reset() {
    rm -f "$QUOTES_FILE" "$PLAYLIST_FILE" "$BOOT_ID_FILE"
    _init
    _rebuild_playlist
    echo -e "  ${O}[✓] Resetado para $(jq 'length' "$QUOTES_FILE") frases embutidas.${R}"
}

_cmd_sync() {
    command -v curl &>/dev/null || { echo -e "  ${T}[!] curl não encontrado.${R}"; exit 1; }
    command -v jq &>/dev/null   || { echo -e "  ${T}[!] jq não encontrado.${R}"; exit 1; }
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA QUOTES — Buscando sabedoria...              ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    _do_sync true
    _rebuild_playlist
    echo -e "  ${O}[✓] Playlist reembaralhada ($(wc -l < "$PLAYLIST_FILE") frases).${R}"
    echo ""
}

_cmd_help() {
    echo ""
    echo -e "  ${B}stoa-quotes-sync${R} — Frases estoicas"
    echo ""
    echo -e "  ${S}Banco:     ${QUOTES_FILE}${R}"
    echo -e "  ${S}Playlist:  ${PLAYLIST_FILE}${R}"
    echo ""
    echo -e "  ${S}Cada app pega uma frase diferente via \"next\".${R}"
    echo -e "  ${S}Sync automático no boot e quando a playlist esvazia.${R}"
    echo ""
    echo -e "  ${S}Comandos:${R}"
    echo -e "    ${O}stoa-quotes-sync${R}             Buscar frases agora"
    echo -e "    ${O}stoa-quotes-sync next${R}        Próxima frase (consome da playlist)"
    echo -e "    ${O}stoa-quotes-sync remaining${R}   Frases restantes na playlist"
    echo -e "    ${O}stoa-quotes-sync list${R}        Listar todas do banco"
    echo -e "    ${O}stoa-quotes-sync count${R}       Total no banco"
    echo -e "    ${O}stoa-quotes-sync add \"...\"${R}   Adicionar frase manual"
    echo -e "    ${O}stoa-quotes-sync reset${R}       Voltar às embutidas"
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
