#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Quotes                                        ║
# ║  "A riqueza consiste não em ter grandes posses, mas em ter  ║
# ║   poucas necessidades." — Epicteto                          ║
# ║                                                              ║
# ║  Arquivo central: ~/.local/share/stoa/quotes.json            ║
# ║  Rotação: a cada 20 minutos (determinística)                 ║
# ║  Sync: 1x por dia, busca ~75 frases novas em background     ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
QUOTES_FILE="$STOA_DIR/quotes.json"
SYNC_STAMP="$STOA_DIR/.quotes-last-sync"
SYNC_LOCK="$STOA_DIR/.quotes-sync.lock"

SYNC_INTERVAL=86400   # 24h entre syncs
ROTATE_INTERVAL=1200  # 20 min entre rotações
FETCH_COUNT=75        # 24h / 20min = 72 slots, busca 75 para margem

# ── Cores (só para output interativo) ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Frases embutidas (fallback offline / seed inicial) ──
_builtin_quotes() {
    cat <<'QUOTES'
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
  "Memento Mori — Remember that you will die.",
  "Amor Fati — Love your fate.",
  "A felicidade depende da qualidade dos teus pensamentos. — Marco Aurélio",
  "Não sofras antes do tempo. — Sêneca",
  "Não é o que te acontece, mas como reages ao que te acontece. — Epicteto",
  "O impedimento à ação avança a ação. O que se interpõe no caminho torna-se o caminho. — Marco Aurélio",
  "A virtude é o único bem. — Zenão de Cítio",
  "Sorte é o que acontece quando a preparação encontra a oportunidade. — Sêneca",
  "A alma torna-se tingida pela cor dos seus pensamentos. — Marco Aurélio",
  "Perde quem se dá por perdido; a coragem não permite a fortuna adversa. — Sêneca",
  "Se queres melhorar, aceita parecer ignorante ou estúpido. — Epicteto"
]
QUOTES
}

# ── Inicializar arquivo se não existir ──
_init() {
    mkdir -p "$STOA_DIR"
    if [ ! -f "$QUOTES_FILE" ]; then
        _builtin_quotes > "$QUOTES_FILE"
    fi
}

# ── APIs de frases estoicas ──
_fetch_one_tekloon() {
    local r
    r=$(curl -sf --max-time 5 "https://stoic.tekloon.net/stoic-quote" 2>/dev/null) || return 1
    local q a
    q=$(printf '%s' "$r" | jq -r '.data.quote // empty' 2>/dev/null)
    a=$(printf '%s' "$r" | jq -r '.data.author // empty' 2>/dev/null)
    [ -n "$q" ] && echo "${q} — ${a}" && return 0
    return 1
}

_fetch_one_stoicapi() {
    local r
    r=$(curl -sf --max-time 5 "https://api.stoicquotesapi.com/v1/api/quotes/random" 2>/dev/null) || return 1
    local q a
    q=$(printf '%s' "$r" | jq -r '.body // .quote // empty' 2>/dev/null)
    a=$(printf '%s' "$r" | jq -r '.author // empty' 2>/dev/null)
    [ -n "$q" ] && echo "${q} — ${a}" && return 0
    return 1
}

# ── Adicionar frase sem duplicar ──
_add_quote() {
    local q="$1"
    if jq -e --arg q "$q" 'map(ascii_downcase == ($q | ascii_downcase)) | any' "$QUOTES_FILE" &>/dev/null; then
        return 1
    fi
    local tmp
    tmp=$(jq --arg q "$q" '. + [$q]' "$QUOTES_FILE") && echo "$tmp" > "$QUOTES_FILE"
}

# ── Sync: busca frases novas da internet ──
_do_sync() {
    local interactive="${1:-false}"
    _init

    # Lock para evitar syncs simultâneos
    if [ -f "$SYNC_LOCK" ]; then
        local lock_age=$(( $(date +%s) - $(stat -c %Y "$SYNC_LOCK" 2>/dev/null || echo 0) ))
        # Lock preso há mais de 5 min? Remover
        [ "$lock_age" -gt 300 ] && rm -f "$SYNC_LOCK" || return 0
    fi
    touch "$SYNC_LOCK"

    local added=0 tried=0

    for i in $(seq 1 "$FETCH_COUNT"); do
        local quote=""
        quote=$(_fetch_one_tekloon) || quote=$(_fetch_one_stoicapi) || true

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

    # Marcar timestamp do sync
    date +%s > "$SYNC_STAMP"
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

# ── Sync automático: verifica se já passou 24h, roda em background ──
_auto_sync() {
    # Precisa de curl e jq
    command -v curl &>/dev/null && command -v jq &>/dev/null || return 0

    local now last_sync age
    now=$(date +%s)

    if [ -f "$SYNC_STAMP" ]; then
        last_sync=$(cat "$SYNC_STAMP" 2>/dev/null || echo 0)
        age=$(( now - last_sync ))
    else
        age=$SYNC_INTERVAL  # nunca sincronizou → forçar
    fi

    if [ "$age" -ge "$SYNC_INTERVAL" ]; then
        # Rodar sync em background (silencioso)
        _do_sync false &
        disown 2>/dev/null
    fi
}

# ── Comando: random ──
# Retorna 1 frase determinística que muda a cada 20 minutos.
# Dispara sync em background se necessário.
_cmd_random() {
    _init

    # Disparar sync diário em background se necessário
    _auto_sync

    local total
    total=$(jq 'length' "$QUOTES_FILE" 2>/dev/null)
    if [ -z "$total" ] || [ "$total" -eq 0 ]; then
        echo "The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius"
        return
    fi

    # Índice determinístico: muda a cada 20 minutos
    local slot=$(( $(date +%s) / ROTATE_INTERVAL ))
    local idx=$(( slot % total ))
    jq -r ".[$idx]" "$QUOTES_FILE"
}

# ── Comando: count ──
_cmd_count() {
    _init
    jq 'length' "$QUOTES_FILE"
}

# ── Comando: list ──
_cmd_list() {
    _init
    jq -r 'to_entries[] | "\(.key + 1). \(.value)"' "$QUOTES_FILE"
}

# ── Comando: add "frase" ──
_cmd_add() {
    local quote="$1"
    if [ -z "$quote" ]; then
        echo -e "  ${T}Uso: stoa-quotes-sync add \"Quote here — Author\"${R}"
        return 1
    fi
    _init
    if _add_quote "$quote"; then
        echo -e "  ${O}[+] Adicionada: ${quote}${R}"
    else
        echo -e "  ${S}[~] Já existe: ${quote}${R}"
    fi
}

# ── Comando: reset ──
_cmd_reset() {
    rm -f "$QUOTES_FILE" "$SYNC_STAMP"
    _init
    local total
    total=$(jq 'length' "$QUOTES_FILE")
    echo -e "  ${O}[✓] Resetado para ${total} frases embutidas.${R}"
}

# ── Comando: sync (interativo) ──
_cmd_sync() {
    if ! command -v curl &>/dev/null; then
        echo -e "  ${T}[!] curl não encontrado. sudo pacman -S curl${R}"; exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo -e "  ${T}[!] jq não encontrado. sudo pacman -S jq${R}"; exit 1
    fi

    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA QUOTES — Buscando sabedoria...              ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""

    _do_sync true
}

# ── Help ──
_cmd_help() {
    echo ""
    echo -e "  ${B}stoa-quotes-sync${R} — Frases estoicas"
    echo ""
    echo -e "  ${S}O arquivo central fica em:${R}"
    echo -e "  ${O}${QUOTES_FILE}${R}"
    echo ""
    echo -e "  ${S}Rotação:  a cada 20 minutos (automática)${R}"
    echo -e "  ${S}Sync:     1x por dia (automático em background)${R}"
    echo ""
    echo -e "  ${S}Comandos:${R}"
    echo -e "    ${O}stoa-quotes-sync${R}            Buscar frases agora (interativo)"
    echo -e "    ${O}stoa-quotes-sync random${R}     Frase atual (muda a cada 20 min)"
    echo -e "    ${O}stoa-quotes-sync list${R}       Listar todas"
    echo -e "    ${O}stoa-quotes-sync count${R}      Total de frases"
    echo -e "    ${O}stoa-quotes-sync add \"...\"${R}  Adicionar frase manual"
    echo -e "    ${O}stoa-quotes-sync reset${R}      Voltar às embutidas"
    echo ""
}

# ── Main ──
case "${1:-}" in
    random)  _cmd_random ;;
    count)   _cmd_count ;;
    list)    _cmd_list ;;
    add)     shift; _cmd_add "$*" ;;
    reset)   _cmd_reset ;;
    help|-h|--help) _cmd_help ;;
    *)       _cmd_sync ;;
esac
