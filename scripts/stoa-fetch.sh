#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoa Fetch                                    ║
# ║  A minimalist fetch with Stoic aesthetics                    ║
# ╚══════════════════════════════════════════════════════════════╝

# Colors
B='\033[38;2;196;154;92m'   # Bronze
G='\033[38;2;212;168;75m'   # Gold
S='\033[38;2;110;106;98m'   # Stone
O='\033[38;2;138;154;108m'  # Olive
F='\033[38;2;212;207;196m'  # Foreground
D='\033[38;2;168;159;145m'  # Dim
T='\033[38;2;179;107;90m'   # Terracotta
R='\033[0m'                 # Reset

# ── Easter egg: Diogenes' plucked chicken ──
if [[ "$1" == "--plato" ]]; then
    # Gather system info first
    user="${USER}@$(hostname)"
    os=$(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -o)
    kernel=$(uname -r)
    up=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")
    sh=$(basename "$SHELL")
    wm="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-Hyprland}}"
    pkgs=$(pacman -Q 2>/dev/null | wc -l || echo "?")
    mem_used=$(free -m | awk '/Mem:/ {print $3}')
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "?")

    clear
    HIDE='\033[?25l'
    SHOW='\033[?25h'
    trap "printf '${SHOW}'; exit" EXIT INT TERM
    printf "${HIDE}"

    # Walking animation — chicken moves right across 8 positions
    for pos in 2 5 8 11 14 17 20 23 20 23 17 20 23; do
        pad=$(printf '%*s' "$pos" '')
        printf '\033[H\033[2J'
        echo ""
        echo -e "  ${pad}${T}  _${R}"
        echo -e "  ${pad}${T} (o>${R}"
        echo -e "  ${pad}${T} //\\\\${R}"
        echo -e "  ${pad}${T} V_/_${R}"
        if (( pos % 6 < 3 )); then
            echo -e "  ${pad}${T}  |/${R}"
            echo -e "  ${pad}${T} _|${R}"
        else
            echo -e "  ${pad}${T}  \\|${R}"
            echo -e "  ${pad}${T}   |_${R}"
        fi
        echo ""
        sleep 0.15
    done

    # Phase 2: chicken stops center
    printf '\033[H\033[2J'
    echo ""
    echo -e "  ${T}                    _${R}"
    echo -e "  ${T}                   (o>${R}"
    echo -e "  ${T}                   //\\\\${R}"
    echo -e "  ${T}                   V_/_${R}"
    echo -e "  ${T}                    ||${R}"
    echo -e "  ${T}                   _/\\_ ${R}"
    echo ""
    sleep 0.7

    # Phase 3: quote appears
    printf '\033[H\033[2J'
    echo ""
    echo -e "  ${T}                    _${R}"
    echo -e "  ${T}                   (o>${R}   ${B}\"Ecce homo${R}"
    echo -e "  ${T}                   //\\\\${R}    ${B}Platonis!\"${R}"
    echo -e "  ${T}                   V_/_${R}"
    echo -e "  ${T}                    ||${R}   ${D}— Diogenes, c. 350 BC${R}"
    echo -e "  ${T}                   _/\\_ ${R}"
    echo ""
    sleep 1.0

    # Phase 4: full scene — chicken + system info + quote
    printf '\033[H\033[2J'
    echo ""
    echo -e "  ${T}         _${R}"
    echo -e "  ${T}        (o>${R}              ${G}${user}${R}"
    echo -e "  ${T}        //\\\\${R}              ${S}──────────────────${R}"
    echo -e "  ${T}        V_/_${R}             ${B}Virtue  ${S}› ${F}${os}${R}"
    echo -e "  ${T}         ||${R}              ${B}Logos   ${S}› ${F}${kernel}${R}"
    echo -e "  ${T}        _/\\_${R}             ${B}Uptime  ${S}› ${F}${up}${R}"
    echo -e "  ${T}   ▄▄▄▄▄▄▄▄▄▄▄▄▄${R}       ${B}Agora   ${S}› ${F}${sh}${R}"
    echo -e "  ${S}   ═══════════════${R}       ${B}Column  ${S}› ${F}${wm}${R}"
    echo -e "                              ${B}Packages${S}› ${F}${pkgs}${R}"
    echo -e "  ${B}  \"Ecce homo Platonis!\"${R}   ${B}Mind    ${S}› ${F}${cpu}${R}"
    echo -e "  ${D}  — Diogenes of Sinope${R}    ${B}Memory  ${S}› ${F}${mem_used}M / ${mem_total}M${R}"
    echo ""
    echo -e "  ${S}┌──┬──┬──┬──┬──┬──┬──┬──┐${R}"
    echo -ne "  "
    echo -ne "${S}│\033[48;2;26;23;20m  ${R}"
    echo -ne "${S}│\033[48;2;179;107;90m  ${R}"
    echo -ne "${S}│\033[48;2;138;154;108m  ${R}"
    echo -ne "${S}│\033[48;2;196;154;92m  ${R}"
    echo -ne "${S}│\033[48;2;90;122;138m  ${R}"
    echo -ne "${S}│\033[48;2;148;106;122m  ${R}"
    echo -ne "${S}│\033[48;2;106;138;122m  ${R}"
    echo -ne "${S}│\033[48;2;212;207;196m  ${R}"
    echo -e "${S}│${R}"
    echo -e "  ${S}└──┴──┴──┴──┴──┴──┴──┴──┘${R}"
    echo ""
    echo -e "  ${D}Plato defined man as a \"featherless biped\".${R}"
    echo -e "  ${D}Diogenes plucked a chicken and stormed the Academy.${R}"
    echo -e "  ${D}Definitions that don't survive a practical test are worthless.${R}"
    echo ""

    printf "${SHOW}"
    exit 0
fi

# Info
user="${USER}@$(hostname)"
os=$(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -o)
kernel=$(uname -r)
uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")
shell=$(basename "$SHELL")
wm="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-Hyprland}}"
pkgs=$(pacman -Q 2>/dev/null | wc -l || echo "?")
mem_used=$(free -m | awk '/Mem:/ {print $3}')
mem_total=$(free -m | awk '/Mem:/ {print $2}')
cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "?")

echo ""
echo -e "  ${B}        ╔═══╗${R}"
echo -e "  ${B}        ║   ║${R}        ${G}${user}${R}"
echo -e "  ${B}        ║   ║${R}        ${S}──────────────────${R}"
echo -e "  ${B}   ╔════╩═══╩════╗${R}   ${B}Virtue  ${S}› ${F}${os}${R}"
echo -e "  ${B}   ║             ║${R}   ${B}Logos   ${S}› ${F}${kernel}${R}"
echo -e "  ${B}   ║      Σ      ║${R}   ${B}Uptime  ${S}› ${F}${uptime}${R}"
echo -e "  ${B}   ║             ║${R}   ${B}Agora   ${S}› ${F}${shell}${R}"
echo -e "  ${B}   ╚═════════════╝${R}   ${B}Column  ${S}› ${F}${wm}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Packages${S}› ${F}${pkgs}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Mind    ${S}› ${F}${cpu}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Memory  ${S}› ${F}${mem_used}M / ${mem_total}M${R}"
echo -e "  ${B}  ═╩═╩═╩═╩═╩═╩═╩═${R}"
echo -e "  ${B}  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${R}"
echo ""
echo -e "  ${S}┌──┬──┬──┬──┬──┬──┬──┬──┐${R}"
echo -ne "  "
echo -ne "${S}│\033[48;2;26;23;20m  ${R}"
echo -ne "${S}│\033[48;2;179;107;90m  ${R}"
echo -ne "${S}│\033[48;2;138;154;108m  ${R}"
echo -ne "${S}│\033[48;2;196;154;92m  ${R}"
echo -ne "${S}│\033[48;2;90;122;138m  ${R}"
echo -ne "${S}│\033[48;2;148;106;122m  ${R}"
echo -ne "${S}│\033[48;2;106;138;122m  ${R}"
echo -ne "${S}│\033[48;2;212;207;196m  ${R}"
echo -e "${S}│${R}"
echo -e "  ${S}└──┴──┴──┴──┴──┴──┴──┴──┘${R}"
echo ""
