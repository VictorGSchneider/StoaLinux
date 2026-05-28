#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Memento Mori Data                             ║
# ║  "Remember that you will die." — Stoic tradition             ║
# ║                                                              ║
# ║  Emits JSON describing how much of each natural cycle has    ║
# ║  elapsed and how much remains — day, week, month, year, and  ║
# ║  the configured life span. Consumed by the eww overlay and   ║
# ║  the Noctalia stoa-memento desktop widget.                   ║
# ║                                                              ║
# ║  Reads ~/.config/stoa/memento.conf (NAME / BIRTH /           ║
# ║  LIFE_YEARS).                                                ║
# ╚══════════════════════════════════════════════════════════════╝

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/memento.conf"

# ── Create default config if it doesn't exist ──
if [ ! -f "$CONF" ]; then
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" <<'DEFAULT'
NAME=Victor Gabriel Schneider
BIRTH=2000-11-01
LIFE_YEARS=80
DEFAULT
    echo "File created: $CONF" >&2
    echo "Edit with your data (name, date of birth, life expectancy)." >&2
fi

# ── Read config ──
# shellcheck source=/dev/null
source "$CONF"

NAME="${NAME:-Victor Gabriel Schneider}"
BIRTH="${BIRTH:-2000-11-01}"
LIFE_YEARS="${LIFE_YEARS:-80}"

# ── Time anchors ──
now=$(date +%s)
birth=$(date -d "$BIRTH" +%s 2>/dev/null || date -d "${BIRTH}T00:00:00" +%s)

# ── Lived (kept for compat with anything still consuming the old fields) ──
days_lived=$(( (now - birth) / 86400 ))
weeks_lived=$(( days_lived / 7 ))
years_lived=$(awk "BEGIN { printf \"%.1f\", ($now - $birth) / 31557600 }")
total_weeks=$(( LIFE_YEARS * 52 ))

# ── Helper: format a seconds count as the most useful 2-unit string ──
fmt_remaining() {
    local s=$1
    if [ "$s" -le 0 ]; then echo "0m"; return; fi
    local d=$(( s / 86400 ))
    local h=$(( (s % 86400) / 3600 ))
    local m=$(( (s % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then
        if [ "$h" -gt 0 ]; then printf '%dd %dh' "$d" "$h"; else printf '%dd' "$d"; fi
    elif [ "$h" -gt 0 ]; then
        printf '%dh %dm' "$h" "$m"
    else
        printf '%dm' "$m"
    fi
}

# ── Day ──
day_start=$(date -d "today 00:00:00" +%s)
day_end=$(date -d "tomorrow 00:00:00" +%s)
day_pct=$(awk "BEGIN { printf \"%.1f\", ($now - $day_start) / ($day_end - $day_start) * 100 }")
day_remaining=$(fmt_remaining $(( day_end - now )))

# ── Week (ISO: Mon = 1, Sun = 7) ──
dow=$(date +%u)
week_elapsed=$(( (dow - 1) * 86400 + (now - day_start) ))
week_total=$(( 7 * 86400 ))
week_pct=$(awk "BEGIN { printf \"%.1f\", $week_elapsed / $week_total * 100 }")
week_remaining=$(fmt_remaining $(( week_total - week_elapsed )))

# ── Month ──
month_start=$(date -d "$(date +%Y-%m-01)" +%s)
month_end=$(date -d "$(date +%Y-%m-01) +1 month" +%s)
month_pct=$(awk "BEGIN { printf \"%.1f\", ($now - $month_start) / ($month_end - $month_start) * 100 }")
month_remaining=$(fmt_remaining $(( month_end - now )))

# ── Year ──
year_start=$(date -d "$(date +%Y)-01-01" +%s)
year_end=$(date -d "$(($(date +%Y) + 1))-01-01" +%s)
year_pct=$(awk "BEGIN { printf \"%.1f\", ($now - $year_start) / ($year_end - $year_start) * 100 }")
year_remaining=$(fmt_remaining $(( year_end - now )))

# ── Life ──
life_total=$(( LIFE_YEARS * 31557600 ))
life_elapsed=$(( now - birth ))
life_pct=$(awk "BEGIN { printf \"%.1f\", $life_elapsed / $life_total * 100 }")
life_remaining_secs=$(( life_total - life_elapsed ))
if [ "$life_remaining_secs" -le 0 ]; then
    life_remaining="0y"
else
    life_remaining=$(awk "BEGIN { printf \"%.1fy\", $life_remaining_secs / 31557600 }")
fi

# ── Stoic quote (consumes next from playlist) ──
quote=""
command -v stoa-quotes-sync &>/dev/null && quote=$(stoa-quotes-sync next 2>/dev/null)
quote="${quote:-The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius}"

# ── Output ──
jq -n \
    --arg  name              "$NAME" \
    --argjson days_lived     "$days_lived" \
    --argjson weeks_lived    "$weeks_lived" \
    --arg  years_lived       "$years_lived" \
    --argjson total_weeks    "$total_weeks" \
    --argjson life_years     "$LIFE_YEARS" \
    --argjson current_year   "$(date +%Y)" \
    --arg  today             "$(date '+%d %b %Y')" \
    --arg  day_pct           "$day_pct" \
    --arg  day_remaining     "$day_remaining" \
    --arg  week_pct          "$week_pct" \
    --arg  week_remaining    "$week_remaining" \
    --arg  month_pct         "$month_pct" \
    --arg  month_remaining   "$month_remaining" \
    --arg  year_pct          "$year_pct" \
    --arg  year_remaining    "$year_remaining" \
    --arg  life_pct          "$life_pct" \
    --arg  life_remaining    "$life_remaining" \
    --arg  quote             "$quote" \
    '{
        name:         $name,
        days_lived:   $days_lived,
        weeks_lived:  $weeks_lived,
        years_lived:  ($years_lived | tonumber),
        total_weeks:  $total_weeks,
        life_years:   $life_years,
        current_year: $current_year,
        today:        $today,
        day_pct:          ($day_pct          | tonumber),
        day_remaining:    $day_remaining,
        week_pct:         ($week_pct         | tonumber),
        week_remaining:   $week_remaining,
        month_pct:        ($month_pct        | tonumber),
        month_remaining:  $month_remaining,
        year_pct:         ($year_pct         | tonumber),
        year_remaining:   $year_remaining,
        life_pct:         ($life_pct         | tonumber),
        life_remaining:   $life_remaining,
        quote:        $quote
    }'
