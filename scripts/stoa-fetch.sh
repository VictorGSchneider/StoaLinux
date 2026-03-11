#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoa Fetch                                    ║
# ║  Um fetch minimalista com estética estoica                   ║
# ╚══════════════════════════════════════════════════════════════╝

# Cores
B='\033[38;2;196;154;92m'   # Bronze
G='\033[38;2;212;168;75m'   # Gold
S='\033[38;2;110;106;98m'   # Stone
O='\033[38;2;138;154;108m'  # Olive
F='\033[38;2;212;207;196m'  # Foreground
D='\033[38;2;168;159;145m'  # Dim
R='\033[0m'                 # Reset

# Info
user="${USER}@$(hostname)"
os=$(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -o)
kernel=$(uname -r)
uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")
shell=$(basename "$SHELL")
wm="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-i3}}"
pkgs=$(pacman -Q 2>/dev/null | wc -l || echo "?")
mem_used=$(free -m | awk '/Mem:/ {print $3}')
mem_total=$(free -m | awk '/Mem:/ {print $2}')
cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "?")

echo ""
echo -e "  ${B}        ╔═══╗${R}"
echo -e "  ${B}        ║   ║${R}        ${G}${user}${R}"
echo -e "  ${B}        ║   ║${R}        ${S}──────────────────${R}"
echo -e "  ${B}   ╔════╩═══╩════╗${R}   ${B}Virtude ${S}› ${F}${os}${R}"
echo -e "  ${B}   ║             ║${R}   ${B}Logos   ${S}› ${F}${kernel}${R}"
echo -e "  ${B}   ║      Σ      ║${R}   ${B}Tempo   ${S}› ${F}${uptime}${R}"
echo -e "  ${B}   ║             ║${R}   ${B}Ágora   ${S}› ${F}${shell}${R}"
echo -e "  ${B}   ╚═════════════╝${R}   ${B}Coluna  ${S}› ${F}${wm}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Pacotes ${S}› ${F}${pkgs}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Mente   ${S}› ${F}${cpu}${R}"
echo -e "  ${B}   ║ ║ ║ ║ ║ ║ ║${R}   ${B}Memória ${S}› ${F}${mem_used}M / ${mem_total}M${R}"
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
