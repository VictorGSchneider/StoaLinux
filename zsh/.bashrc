# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bash                                          ║
# ║  "Primeiro diga a si mesmo o que seria; depois faça         ║
# ║   o que tem de fazer." — Epicteto                            ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Citação Estoica ──
# Lê de ~/.local/share/stoa/current (atualizado a cada 20 min)

_stoa_greeting() {
    local current="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/current"
    local quote=""
    [ -s "$current" ] && quote=$(cat "$current")
    # Tick em background: avança frase se >20min, sync se boot novo/playlist vazia
    command -v stoa-quotes-sync &>/dev/null && stoa-quotes-sync tick &>/dev/null &
    quote="${quote:-The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius}"
    echo ""
    echo -e "  \033[38;2;196;154;92m╔══════════════════════════════════════════════════════╗\033[0m"
    echo -e "  \033[38;2;196;154;92m║\033[0m  \033[38;2;212;207;196;3m${quote}\033[0m"
    echo -e "  \033[38;2;196;154;92m╚══════════════════════════════════════════════════════╝\033[0m"
    echo ""
}
_stoa_greeting

# ── Histórico ──
HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
shopt -s histappend

# ── Prompt Estoico ──
_stoa_prompt() {
    local exit_code=$?
    local bronze='\[\033[38;2;196;154;92m\]'
    local stone='\[\033[38;2;110;106;98m\]'
    local olive='\[\033[38;2;138;154;108m\]'
    local terracotta='\[\033[38;2;179;107;90m\]'
    local reset='\[\033[0m\]'

    local git_branch=""
    if git rev-parse --git-dir &>/dev/null; then
        git_branch=" ${olive}$(git branch --show-current 2>/dev/null)${reset}"
    fi

    local status_indicator=""
    if [ $exit_code -ne 0 ]; then
        status_indicator=" ${terracotta}[${exit_code}]${reset}"
    fi

    PS1="${stone}\w${reset}${git_branch} ${bronze}Ι${reset}${status_indicator} "
}
PROMPT_COMMAND=_stoa_prompt

# ── Aliases ──
alias ls='ls --color=auto'
alias ll='ls -lAh --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias vim='nvim'
alias vi='nvim'
alias ..='cd ..'
alias ...='cd ../..'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias cls='clear'

# ── Ambiente Stoa (toolkits + apps padrão) ──
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa-env.sh" ] && \
    source "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa-env.sh"

# ── Cores ──
export LS_COLORS='di=38;2;196;154;92:ln=38;2;90;122;138:ex=38;2;138;154;108:*.tar=38;2;179;107;90:*.gz=38;2;179;107;90:*.zip=38;2;179;107;90:*.jpg=38;2;148;106;122:*.png=38;2;148;106;122:*.mp3=38;2;164;122;138:*.mp4=38;2;164;122;138'

export LESS_TERMCAP_mb=$'\e[1;38;2;179;107;90m'
export LESS_TERMCAP_md=$'\e[1;38;2;196;154;92m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;38;2;33;30;25;48;2;196;154;92m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;38;2;138;154;108m'

# ── Caminho ──
export PATH="$HOME/.local/bin:$PATH"
