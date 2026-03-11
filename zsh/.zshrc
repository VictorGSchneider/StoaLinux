# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Zsh                                           ║
# ║  "Primeiro diga a si mesmo o que seria; depois faça         ║
# ║   o que tem de fazer." — Epicteto                            ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Citações Estoicas (exibida ao abrir o terminal) ──
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

# ── Exibir citação ao iniciar ──
_stoa_greeting() {
    local idx=$(( RANDOM % ${#stoa_quotes[@]} + 1 ))
    local quote="${stoa_quotes[$idx]}"
    echo ""
    echo "  \033[38;2;196;154;92m╔══════════════════════════════════════════════════════╗\033[0m"
    echo "  \033[38;2;196;154;92m║\033[0m  \033[38;2;212;207;196;3m${quote}\033[0m"
    echo "  \033[38;2;196;154;92m╚══════════════════════════════════════════════════════╝\033[0m"
    echo ""
}
_stoa_greeting

# ── Histórico ──
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups
setopt hist_ignore_space

# ── Completar ──
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# ── Vi mode ──
bindkey -v
export KEYTIMEOUT=1

# ── Prompt Estoico ──
# Símbolo: coluna grega (Ι) em bronze
autoload -Uz vcs_info
precmd() { vcs_info }
setopt prompt_subst

zstyle ':vcs_info:git:*' formats ' %F{#8a9a6c}%b%f'

PROMPT='%F{#6e6a62}%~%f${vcs_info_msg_0_} %F{#c49a5c}Ι%f '
RPROMPT='%(?..%F{#b36b5a}[%?]%f)'

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

# ── Variáveis ──
export EDITOR='nvim'
export VISUAL='nvim'
export TERMINAL='alacritty'
export BROWSER='firefox'

# ── Cores para ls ──
export LS_COLORS='di=38;2;196;154;92:ln=38;2;90;122;138:ex=38;2;138;154;108:*.tar=38;2;179;107;90:*.gz=38;2;179;107;90:*.zip=38;2;179;107;90:*.jpg=38;2;148;106;122:*.png=38;2;148;106;122:*.mp3=38;2;164;122;138:*.mp4=38;2;164;122;138'

# ── Caminho ──
export PATH="$HOME/.local/bin:$PATH"

# ── Man pages coloridas (paleta estoica) ──
export LESS_TERMCAP_mb=$'\e[1;38;2;179;107;90m'
export LESS_TERMCAP_md=$'\e[1;38;2;196;154;92m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;38;2;33;30;25;48;2;196;154;92m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;38;2;138;154;108m'
