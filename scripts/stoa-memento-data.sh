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

# ── Frase estoica (mesmas do zsh/.zshrc) ──
stoa_quotes=(
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

idx=$(( RANDOM % ${#stoa_quotes[@]} ))
quote="${stoa_quotes[$idx]}"

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
    "quote": "$quote"
}
JSON
