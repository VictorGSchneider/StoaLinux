#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Data                             ║
# ║  "Lembra-te de que vais morrer." — tradição estoica          ║
# ║                                                              ║
# ║  Gera dados JSON para o widget eww Memento Mori.            ║
# ║  Lê ~/.config/stoa/memento.conf para configuração.           ║
# ╚══════════════════════════════════════════════════════════════╝

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/memento.conf"

# ── Criar config padrão se não existir ──
if [ ! -f "$CONF" ]; then
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" <<'DEFAULT'
NAME=Marcus
BIRTH=1990-01-01
LIFE_YEARS=80
DEFAULT
    echo "Arquivo criado: $CONF" >&2
    echo "Edite com seus dados (nome, data de nascimento, expectativa de vida)." >&2
fi

# ── Ler config ──
source "$CONF"

NAME="${NAME:-Marcus}"
BIRTH="${BIRTH:-1990-01-01}"
LIFE_YEARS="${LIFE_YEARS:-80}"

# ── Cálculos ──
today=$(date +%s)
birth=$(date -d "$BIRTH" +%s 2>/dev/null || date -d "${BIRTH}T00:00:00" +%s)

days_lived=$(( (today - birth) / 86400 ))
weeks_lived=$(( days_lived / 7 ))

# Anos vividos com 1 casa decimal
years_seconds=$(( today - birth ))
years_lived=$(awk "BEGIN { printf \"%.1f\", $years_seconds / 31557600 }")

# Progresso do ano atual
year_start=$(date -d "$(date +%Y)-01-01" +%s)
year_end=$(date -d "$(($(date +%Y) + 1))-01-01" +%s)
year_pct=$(awk "BEGIN { printf \"%.1f\", ($today - $year_start) / ($year_end - $year_start) * 100 }")

# Total de semanas na vida
total_weeks=$(( LIFE_YEARS * 52 ))

# ── Frase estoica (lê de ~/.local/share/stoa/current) ──
_current="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/current"
quote=""
[ -s "$_current" ] && quote=$(cat "$_current")
# Tick: avança frase se >20min, sync se boot novo/playlist vazia
command -v stoa-quotes-sync &>/dev/null && stoa-quotes-sync tick &>/dev/null &
quote="${quote:-The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius}"

# Escapar aspas duplas no quote para JSON válido
quote_escaped="${quote//\"/\\\"}"

# ── Output JSON ──
cat <<JSON
{
    "name": "$NAME",
    "days_lived": $days_lived,
    "weeks_lived": $weeks_lived,
    "years_lived": $years_lived,
    "year_pct": $year_pct,
    "total_weeks": $total_weeks,
    "life_years": $LIFE_YEARS,
    "current_year": $(date +%Y),
    "today": "$(date '+%d %b %Y')",
    "quote": "$quote_escaped"
}
JSON
