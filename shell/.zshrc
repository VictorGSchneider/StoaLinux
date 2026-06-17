# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Zsh                                           ║
# ║  "First say to yourself what you would be; and then do      ║
# ║   what you have to do." — Epictetus                          ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Stoic Quote (each terminal gets a different quote) ──

_stoa_greeting() {
    local quote=""
    command -v stoa-quotes-sync &>/dev/null && quote=$(stoa-quotes-sync next 2>/dev/null)
    quote="${quote:-The happiness of your life depends upon the quality of your thoughts. — Marcus Aurelius}"
    echo ""
    echo "  \033[38;2;196;154;92m╔══════════════════════════════════════════════════════╗\033[0m"
    echo "  \033[38;2;196;154;92m║\033[0m  \033[38;2;212;207;196;3m${quote}\033[0m"
    echo "  \033[38;2;196;154;92m╚══════════════════════════════════════════════════════╝\033[0m"
    echo ""
}
_stoa_greeting

# ── History ──
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups
setopt hist_ignore_space

# ── Completion ──
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' completer _expand _complete _ignored _approximate
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.cache/zsh
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin
zstyle ':completion:*:*:*:*:descriptions' format '%F{#c49a5c}-- %d --%f'
zstyle ':completion:*:options' description 'yes'

# ── Vi mode ──
bindkey -v
export KEYTIMEOUT=1

# ── Stoic Prompt ──
# Symbol: Greek column (Ι) in bronze
autoload -Uz vcs_info
precmd() { vcs_info; }
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
alias update='sudo pacman -Syu'
alias update-aur='yay -Syu'
alias update-all='sudo pacman -Syu && yay -Syu'
alias search='yay -Ss'
alias install='sudo pacman -S'
alias install-aur='yay -S'
alias remove='sudo pacman -R'
alias clean='sudo pacman -Rns $(pacman -Qtdq)'
alias list-explicit='pacman -Qe'
alias sync-stoa='stoa-sync'
alias commit-all='git add -A && git commit -m "$(printf 'chore: sync %s\n\nChanges:\n%s' \
    "$(date '+%Y-%m-%d %H:%M')" \
    "$(git diff --cached --name-status)")"'

# ── Stoa Environment (toolkits + default apps) ──
[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa-env.sh" ] && \
    source "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa-env.sh"

# ── Colors for ls ──
export LS_COLORS='di=38;2;196;154;92:ln=38;2;90;122;138:ex=38;2;138;154;108:*.tar=38;2;179;107;90:*.gz=38;2;179;107;90:*.zip=38;2;179;107;90:*.jpg=38;2;148;106;122:*.png=38;2;148;106;122:*.mp3=38;2;164;122;138:*.mp4=38;2;164;122;138'

# ── Path ──
export PATH="$HOME/.local/bin:$PATH"

# ── Colored man pages (Stoic palette) ──
export LESS_TERMCAP_mb=$'\e[1;38;2;179;107;90m'
export LESS_TERMCAP_md=$'\e[1;38;2;196;154;92m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;38;2;212;207;196;48;2;196;154;92m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[4;38;2;138;154;108m'
