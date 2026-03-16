#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Quotes Sync                                   ║
# ║  "A riqueza consiste não em ter grandes posses, mas em ter  ║
# ║   poucas necessidades." — Epicteto                          ║
# ║                                                              ║
# ║  Busca frases estoicas da internet e salva localmente.       ║
# ║  Uso: stoa-quotes-sync [N]   (padrão: 20 frases novas)      ║
# ╚══════════════════════════════════════════════════════════════╝

QUOTES_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/quotes.json"
QUOTES_DIR="$(dirname "$QUOTES_FILE")"

# ── Cores ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Quantas frases buscar ──
COUNT="${1:-20}"

# ── Frases embutidas (fallback offline) ──
BUILTIN_QUOTES=(
    "A felicidade depende da qualidade dos teus pensamentos. — Marco Aurélio"
    "Não sofras antes do tempo. — Sêneca"
    "Não é o que te acontece, mas como reages ao que te acontece. — Epicteto"
    "A riqueza consiste não em ter grandes posses, mas em ter poucas necessidades. — Epicteto"
    "O impedimento à ação avança a ação. O que se interpõe no caminho torna-se o caminho. — Marco Aurélio"
    "Temos duas orelhas e uma boca para ouvir o dobro do que falamos. — Zenão de Cítio"
    "A virtude é o único bem. — Zenão de Cítio"
    "Quem vive sem loucura não é tão sábio quanto pensa. — Sêneca"
    "Sorte é o que acontece quando a preparação encontra a oportunidade. — Sêneca"
    "Se queres melhorar, aceita parecer ignorante ou estúpido. — Epicteto"
    "Perde quem se dá por perdido; a coragem não permite a fortuna adversa. — Sêneca"
    "Ama o teu destino. — Nietzsche (inspirado nos estoicos)"
    "A alma torna-se tingida pela cor dos seus pensamentos. — Marco Aurélio"
    "Memento Mori — Lembra-te de que vais morrer."
    "Amor Fati — Ama o teu destino."
)

# ── Verificar dependências ──
if ! command -v curl &>/dev/null; then
    echo -e "  ${T}[!] curl não encontrado. Instale: sudo pacman -S curl${R}"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo -e "  ${T}[!] jq não encontrado. Instale: sudo pacman -S jq${R}"
    exit 1
fi

# ── Inicializar arquivo se não existir ──
_init_quotes_file() {
    mkdir -p "$QUOTES_DIR"
    if [ ! -f "$QUOTES_FILE" ]; then
        # Criar com frases embutidas
        local json="["
        for i in "${!BUILTIN_QUOTES[@]}"; do
            local q="${BUILTIN_QUOTES[$i]}"
            local escaped
            escaped=$(printf '%s' "$q" | jq -Rs '.')
            [ "$i" -gt 0 ] && json+=","
            json+=$'\n'"  $escaped"
        done
        json+=$'\n'"]"
        echo "$json" > "$QUOTES_FILE"
        echo -e "  ${O}[+] Arquivo criado com ${#BUILTIN_QUOTES[@]} frases embutidas.${R}"
    fi
}

# ── Buscar de stoic.tekloon.net ──
_fetch_tekloon() {
    local result
    result=$(curl -sf --max-time 5 "https://stoic.tekloon.net/stoic-quote" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        local quote author
        quote=$(echo "$result" | jq -r '.data.quote // empty' 2>/dev/null)
        author=$(echo "$result" | jq -r '.data.author // empty' 2>/dev/null)
        if [ -n "$quote" ]; then
            echo "${quote} — ${author}"
            return 0
        fi
    fi
    return 1
}

# ── Buscar de stoicquotesapi.com ──
_fetch_stoicapi() {
    local result
    result=$(curl -sf --max-time 5 "https://api.stoicquotesapi.com/v1/api/quotes/random" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        local quote author
        quote=$(echo "$result" | jq -r '.body // .quote // empty' 2>/dev/null)
        author=$(echo "$result" | jq -r '.author // empty' 2>/dev/null)
        if [ -n "$quote" ]; then
            echo "${quote} — ${author}"
            return 0
        fi
    fi
    return 1
}

# ── Adicionar frase ao arquivo (sem duplicar) ──
_add_quote() {
    local new_quote="$1"
    # Verificar se já existe
    if jq -e --arg q "$new_quote" 'map(. == $q) | any' "$QUOTES_FILE" &>/dev/null; then
        return 1  # duplicada
    fi
    # Adicionar
    local tmp
    tmp=$(jq --arg q "$new_quote" '. + [$q]' "$QUOTES_FILE")
    echo "$tmp" > "$QUOTES_FILE"
    return 0
}

# ── Comando: sync ──
_cmd_sync() {
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA QUOTES — Buscando sabedoria...              ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""

    _init_quotes_file

    local before after added fetched
    before=$(jq 'length' "$QUOTES_FILE")
    added=0
    fetched=0

    for i in $(seq 1 "$COUNT"); do
        local quote=""

        # Tentar APIs em ordem
        quote=$(_fetch_tekloon) || quote=$(_fetch_stoicapi) || true

        if [ -n "$quote" ]; then
            fetched=$((fetched + 1))
            if _add_quote "$quote"; then
                added=$((added + 1))
                echo -e "  ${O}[+]${R} ${quote}"
            else
                echo -e "  ${S}[~]${R} (duplicada) ${quote:0:60}..."
            fi
        else
            echo -e "  ${T}[!]${R} Falha ao buscar frase $i"
        fi

        # Pausa entre requests para não abusar da API
        [ "$i" -lt "$COUNT" ] && sleep 0.5
    done

    after=$(jq 'length' "$QUOTES_FILE")
    echo ""
    echo -e "  ${B}Resultado:${R}"
    echo -e "  ${S}  Buscadas:  ${fetched}${R}"
    echo -e "  ${S}  Novas:     ${added}${R}"
    echo -e "  ${S}  Total:     ${after} frases${R}"
    echo -e "  ${S}  Arquivo:   ${QUOTES_FILE}${R}"
    echo ""
}

# ── Comando: random (retorna 1 frase aleatória) ──
_cmd_random() {
    _init_quotes_file
    jq -r '.[ env.idx | tonumber ]' --arg idx "" "$QUOTES_FILE" 2>/dev/null || true
    # Forma mais simples:
    local total
    total=$(jq 'length' "$QUOTES_FILE")
    if [ "$total" -eq 0 ]; then
        echo "${BUILTIN_QUOTES[$((RANDOM % ${#BUILTIN_QUOTES[@]}))]}"
        return
    fi
    local idx=$(( RANDOM % total ))
    jq -r ".[$idx]" "$QUOTES_FILE"
}

# ── Comando: count ──
_cmd_count() {
    _init_quotes_file
    jq 'length' "$QUOTES_FILE"
}

# ── Comando: list ──
_cmd_list() {
    _init_quotes_file
    jq -r '.[]' "$QUOTES_FILE"
}

# ── Comando: add "frase" ──
_cmd_add() {
    local quote="$1"
    if [ -z "$quote" ]; then
        echo -e "  ${T}Uso: stoa-quotes-sync add \"Frase aqui — Autor\"${R}"
        return 1
    fi
    _init_quotes_file
    if _add_quote "$quote"; then
        echo -e "  ${O}[+] Adicionada: ${quote}${R}"
    else
        echo -e "  ${S}[~] Já existe: ${quote}${R}"
    fi
}

# ── Comando: reset (volta às embutidas) ──
_cmd_reset() {
    rm -f "$QUOTES_FILE"
    _init_quotes_file
    echo -e "  ${O}[✓] Resetado para ${#BUILTIN_QUOTES[@]} frases embutidas.${R}"
}

# ── Main ──
case "${1:-}" in
    random)  _cmd_random ;;
    count)   _cmd_count ;;
    list)    _cmd_list ;;
    add)     shift; _cmd_add "$*" ;;
    reset)   _cmd_reset ;;
    help|-h|--help)
        echo ""
        echo -e "  ${B}stoa-quotes-sync${R} — Gerenciador de frases estoicas"
        echo ""
        echo -e "  ${S}Comandos:${R}"
        echo -e "    ${O}stoa-quotes-sync [N]${R}      Buscar N frases novas (padrão: 20)"
        echo -e "    ${O}stoa-quotes-sync random${R}   Exibir 1 frase aleatória"
        echo -e "    ${O}stoa-quotes-sync list${R}     Listar todas as frases"
        echo -e "    ${O}stoa-quotes-sync count${R}    Contar total de frases"
        echo -e "    ${O}stoa-quotes-sync add \"...\"${R} Adicionar frase manual"
        echo -e "    ${O}stoa-quotes-sync reset${R}    Resetar para frases embutidas"
        echo ""
        ;;
    *)
        # Se é número, usa como COUNT
        if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
            COUNT="$1"
        fi
        _cmd_sync
        ;;
esac
