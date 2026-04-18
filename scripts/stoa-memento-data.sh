#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Data                             ║
# ║  "Remember that you will die." — Stoic tradition             ║
# ║                                                              ║
# ║  Generates JSON data for the eww Memento Mori widget.       ║
# ║  Reads ~/.config/stoa/memento.conf for configuration.        ║
# ╚══════════════════════════════════════════════════════════════╝

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/memento.conf"

# ── Create default config if it doesn't exist ──
if [ ! -f "$CONF" ]; then
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" <<'DEFAULT'
NAME=Marcus
BIRTH=1990-01-01
LIFE_YEARS=80
DEFAULT
    echo "File created: $CONF" >&2
    echo "Edit with your data (name, date of birth, life expectancy)." >&2
fi

# ── Read config ──
source "$CONF"

NAME="${NAME:-Marcus}"
BIRTH="${BIRTH:-1990-01-01}"
LIFE_YEARS="${LIFE_YEARS:-80}"

# ── Calculations ──
today=$(date +%s)
birth=$(date -d "$BIRTH" +%s 2>/dev/null || date -d "${BIRTH}T00:00:00" +%s)

days_lived=$(( (today - birth) / 86400 ))
weeks_lived=$(( days_lived / 7 ))

# Years lived with 1 decimal
years_seconds=$(( today - birth ))
years_lived=$(awk "BEGIN { printf \"%.1f\", $years_seconds / 31557600 }")

# Current year progress
year_start=$(date -d "$(date +%Y)-01-01" +%s)
year_end=$(date -d "$(($(date +%Y) + 1))-01-01" +%s)
year_pct=$(awk "BEGIN { printf \"%.1f\", ($today - $year_start) / ($year_end - $year_start) * 100 }")

# Total weeks in lifetime
total_weeks=$(( LIFE_YEARS * 52 ))

# ── Stoic quote (consumes next from playlist) ──
quote=""
command -v stoa-quotes-sync &>/dev/null && quote=$(stoa-quotes-sync next 2>/dev/null)
quote="${quote:-The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius}"

# ── Output JSON (using jq for safe escaping) ──
jq -n \
    --arg name "$NAME" \
    --argjson days_lived "$days_lived" \
    --argjson weeks_lived "$weeks_lived" \
    --arg years_lived "$years_lived" \
    --arg year_pct "$year_pct" \
    --argjson total_weeks "$total_weeks" \
    --argjson life_years "$LIFE_YEARS" \
    --argjson current_year "$(date +%Y)" \
    --arg today "$(date '+%d %b %Y')" \
    --arg quote "$quote" \
    '{
        name: $name,
        days_lived: $days_lived,
        weeks_lived: $weeks_lived,
        years_lived: ($years_lived | tonumber),
        year_pct: ($year_pct | tonumber),
        total_weeks: $total_weeks,
        life_years: $life_years,
        current_year: $current_year,
        today: $today,
        quote: $quote
    }'
