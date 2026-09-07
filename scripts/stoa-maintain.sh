#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — System Maintenance (BRCS)                     ║
# ║  "Order your mind, order your world." — Marcus Aurelius      ║
# ║                                                              ║
# ║  Backup, Restore, Cleanup & Schedule.                        ║
# ║  Based on BRCS.sh by Victor G. Schneider (GPL-3.0)          ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   stoa-maintain                          # Interactive menu
#   stoa-maintain --backup                 # Backup all configs
#   stoa-maintain --restore backup.zip     # Restore all from backup
#   stoa-maintain --restore-interactive backup.zip  # Restore with prompts
#   stoa-maintain --cleanup                # Full system cleanup
#   stoa-maintain --dry-run --cleanup      # Preview cleanup actions
#   stoa-maintain --cleanup --unattended   # Safe subset (what the boot job runs)
#   stoa-maintain --list backup.zip        # Show backup contents
#   stoa-maintain --schedule               # Schedule cleanup at boot

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

VERSION="2.0.0-stoa"

# ── Colors (Stoa palette) ──
B='\033[38;2;196;154;92m'    # Bronze
S='\033[38;2;110;106;98m'    # Stone
F='\033[38;2;212;207;196m'   # Foreground
O='\033[38;2;138;154;108m'   # Olive
T='\033[38;2;179;107;90m'    # Terracotta
R='\033[0m'                   # Reset

# ── Globals ──
MY_HOSTNAME="${HOSTNAME:-$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)}"
TODAY=$(date +%Y%m%d)
# Anchored to $HOME like the log below it: unanchored, the backup landed
# in whatever directory you happened to run from — and stoa-settings'
# restore browser and the health widget both only ever look in $HOME,
# so those backups were invisible to the rest of the system.
# Resolve through the install-time symlink so ~/.local/bin/stoa-maintain
# still finds the shared path definitions in-tree — same trick stoa-store
# uses for its modules.
_STOA_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"
if [ ! -r "$_STOA_LIB/stoa-paths.sh" ]; then
    echo "stoa-maintain: missing $_STOA_LIB/stoa-paths.sh" >&2
    exit 1
fi
# shellcheck source=lib/stoa-paths.sh
source "$_STOA_LIB/stoa-paths.sh"

arq="$STOA_BACKUP_DIR/$MY_HOSTNAME.confs.$TODAY.zip"
log="$STOA_LOG_DIR/backup_$TODAY.log"
USER_DIR="$HOME"
DRY_RUN=0

# ── Detect package manager ──
detect_pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v apk >/dev/null 2>&1; then
        echo "apk"
    else
        echo "unknown"
    fi
}

PKG_MANAGER=$(detect_pkg_manager)

# ── Helpers ──

log_msg() {
    local level="$1"; shift
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    case "$level" in
        INFO)  color="$O" ;;
        WARN)  color="$B" ;;
        ERROR) color="$T" ;;
    esac
    printf "${color}  [%s] [%s]${R} %s\n" "$ts" "$level" "$*"
    echo "[$ts] [$level] $*" >> "$log" 2>/dev/null
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log_msg INFO "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# ── Cleanup scope ──
# "full" is every step, for a person watching it run. "safe" is what a
# scheduled, unattended run is allowed to do on its own: delete garbage and
# change nothing else. It leaves out the system upgrade and orphan removal
# (those alter what is installed, unwatched), old-kernel removal, docker
# prune (stopped containers are someone's work), and the Steam step —
# the shader cache is regenerable, but rebuilding it costs a stuttering
# first launch per game, so wiping it every boot is worse than useless.
CLEANUP_SCOPE="full"
_SAFE_STEPS=" clean flatpak journal stoa tmp "

_step() {
    [ "$CLEANUP_SCOPE" = "full" ] && return 0
    case "$_SAFE_STEPS" in *" $1 "*) return 0 ;; esac
    return 1
}

check_root() {
    [ "$(id -u)" -eq 0 ] && return 0

    if ! command -v sudo >/dev/null 2>&1; then
        log_msg ERROR "Needs root and sudo is not installed."
        return 1
    fi

    # Unattended and unprivileged is the dangerous combination. Every sudo
    # below would be a PAM auth attempt with no terminal to prompt on; PAM
    # logs each as "conversation failed" and pam_faillock counts it. Three
    # is the Arch default, and the account is then locked for ten minutes
    # — at the login screen, on the next boot. Refuse once, loudly, rather
    # than trip that.
    if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
        log_msg ERROR "Needs root, but there is no terminal to ask for a password."
        log_msg ERROR "Run it as root, or grant this user a NOPASSWD sudoers rule."
        return 1
    fi
    return 0
}

# Signal trap for temp file cleanup
_BRCS_TEMPFILES=()
_brcs_cleanup() {
    for f in "${_BRCS_TEMPFILES[@]}"; do
        [ -e "$f" ] && rm -rf "$f"
    done
}

collect_files() {
    local dir="$1"
    _collected_files=()
    while IFS= read -r -d '' f; do
        _collected_files+=("$f")
    done < <(find "$dir" -type f -print0 2>/dev/null)
}

progress_bar() {
    local total=$1
    local current=$2
    local bar_length=30

    if [ "$total" -eq 0 ]; then
        percent=100
        filled=$bar_length
        empty=0
    else
        percent=$((current * 100 / total))
        filled=$((bar_length * percent / 100))
        empty=$((bar_length - filled))
    fi

    local bar_fill="" bar_empty=""
    local i
    for ((i = 0; i < filled; i++)); do bar_fill+="█"; done
    for ((i = 0; i < empty; i++)); do bar_empty+="░"; done

    printf "\r  ${B}[${O}%s${S}%s${B}]${R} %3d%%" "$bar_fill" "$bar_empty" "$percent"
    [ "$current" -eq "$total" ] && echo
}

search_files() {
    local pattern="$1"
    if command -v locate >/dev/null 2>&1; then
        locate "$pattern" 2>/dev/null
    else
        find / -name "*${pattern}" -type f 2>/dev/null
    fi
}

get_repo_patterns() {
    case "$PKG_MANAGER" in
        apt)    echo "/etc/apt/sources.list /etc/apt/sources.list.d" ;;
        dnf|yum) echo "/etc/yum.repos.d" ;;
        pacman) echo "/etc/pacman.conf /etc/pacman.d" ;;
        zypper) echo "/etc/zypp/repos.d" ;;
        apk)    echo "/etc/apk/repositories" ;;
        *)      echo "" ;;
    esac
}

get_disk_used_kb() {
    df / | awk 'NR==2{print $3}'
}

# ── Backup ──

backup_configs() {
    stoa_paths_init
    log_msg INFO "Starting backup..."

    if ! command -v zip >/dev/null 2>&1; then
        log_msg ERROR "'zip' is not installed. Please install it first."
        return 1
    fi

    local repo_patterns
    repo_patterns=$(get_repo_patterns)

    local total=0 count=0
    local all_files=""

    for ext in .conf .ini .rules; do
        local found
        found=$(search_files "$ext" | grep '/etc/')
        [ -n "$found" ] && all_files+="$found"$'\n'
    done

    local found_sh
    found_sh=$(search_files ".sh" | grep '\.sh$' | grep "$USER_DIR")
    [ -n "$found_sh" ] && all_files+="$found_sh"$'\n'

    for sysfile in /etc/fstab /etc/default/grub /etc/hostname /etc/resolv.conf /etc/hosts /etc/locale.conf /etc/vconsole.conf /etc/environment; do
        [ -f "$sysfile" ] && all_files+="$sysfile"$'\n'
    done

    for repo_path in $repo_patterns; do
        if [ -f "$repo_path" ]; then
            all_files+="$repo_path"$'\n'
        elif [ -d "$repo_path" ]; then
            local repo_files
            repo_files=$(find "$repo_path" -type f 2>/dev/null)
            [ -n "$repo_files" ] && all_files+="$repo_files"$'\n'
        fi
    done

    for dotfile in .bashrc .bash_profile .bash_aliases .profile .zshrc .zprofile .vimrc .nanorc .gitconfig .tmux.conf .inputrc .wgetrc .curlrc; do
        [ -f "$USER_DIR/$dotfile" ] && all_files+="$USER_DIR/$dotfile"$'\n'
    done

    if [ -d "$USER_DIR/.config" ]; then
        local cfg_files
        cfg_files=$(find "$USER_DIR/.config" -maxdepth 3 -type f \( -name '*.conf' -o -name '*.ini' -o -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
        [ -n "$cfg_files" ] && all_files+="$cfg_files"$'\n'
    fi

    for crontab_path in "/var/spool/cron/crontabs/$(whoami)" "/var/spool/cron/$(whoami)" /etc/crontab; do
        [ -f "$crontab_path" ] && all_files+="$crontab_path"$'\n'
    done
    if [ -d /etc/cron.d ]; then
        local cron_files
        cron_files=$(find /etc/cron.d -type f 2>/dev/null)
        [ -n "$cron_files" ] && all_files+="$cron_files"$'\n'
    fi

    for unit_dir in /etc/systemd/system /etc/systemd/user "$USER_DIR/.config/systemd/user"; do
        if [ -d "$unit_dir" ]; then
            local unit_files
            unit_files=$(find "$unit_dir" -maxdepth 2 -type f \( -name '*.service' -o -name '*.timer' -o -name '*.mount' -o -name '*.target' -o -name '*.socket' \) 2>/dev/null)
            [ -n "$unit_files" ] && all_files+="$unit_files"$'\n'
        fi
    done

    for ssh_file in "$USER_DIR/.ssh/config" "$USER_DIR/.ssh/authorized_keys" /etc/ssh/sshd_config /etc/ssh/ssh_config; do
        [ -f "$ssh_file" ] && all_files+="$ssh_file"$'\n'
    done

    for fw_file in /etc/iptables/rules.v4 /etc/iptables/rules.v6 /etc/nftables.conf /etc/firewalld/firewalld.conf /etc/ufw/ufw.conf; do
        [ -f "$fw_file" ] && all_files+="$fw_file"$'\n'
    done
    if [ -d /etc/firewalld/zones ]; then
        local fwz
        fwz=$(find /etc/firewalld/zones -type f 2>/dev/null)
        [ -n "$fwz" ] && all_files+="$fwz"$'\n'
    fi

    for net_dir in /etc/NetworkManager/system-connections /etc/netplan /etc/sysconfig/network-scripts /etc/systemd/network; do
        if [ -d "$net_dir" ]; then
            local net_files
            net_files=$(find "$net_dir" -type f 2>/dev/null)
            [ -n "$net_files" ] && all_files+="$net_files"$'\n'
        fi
    done

    all_files=$(echo "$all_files" | sort -u | sed '/^$/d')

    if [ -z "$all_files" ]; then
        log_msg WARN "No configuration files found."
        return 1
    fi

    local line_count
    line_count=$(echo "$all_files" | wc -l)
    total=$line_count

    echo "$all_files" | while IFS= read -r filepath; do
        echo "$filepath"
        count=$((count + 1))
        progress_bar "$total" "$count" >&2
    done | zip "$arq" -r -9 -@ >> "$log" 2>&1

    local file_count
    file_count=$(echo "$all_files" | wc -l)
    local archive_size
    archive_size=$(du -h "$arq" 2>/dev/null | cut -f1)

    log_msg INFO "Backup saved as: $arq ($file_count files, $archive_size)"
}

# ── List backup contents ──

list_backup_contents() {
    local backup_file="${1:-}"
    [ -z "$backup_file" ] && read -r -p "  Enter the path to the backup file (.zip): " backup_file
    [ ! -f "$backup_file" ] && log_msg ERROR "File not found: $backup_file" && return 1

    if ! unzip -t "$backup_file" >/dev/null 2>&1; then
        log_msg ERROR "Invalid or corrupted zip file: $backup_file"
        return 1
    fi

    log_msg INFO "Contents of: $backup_file"
    unzip -l "$backup_file"
}

# ── Restore (interactive) ──

restore_interactive() {
    check_root

    local backup_file="${1:-}"
    [ -z "$backup_file" ] && read -r -p "  Enter the path to the backup file (.zip): " backup_file
    [ ! -f "$backup_file" ] && log_msg ERROR "File not found." && return 1

    if ! command -v unzip >/dev/null 2>&1; then
        log_msg ERROR "'unzip' is not installed. Please install it first."
        return 1
    fi

    if ! unzip -t "$backup_file" >/dev/null 2>&1; then
        log_msg ERROR "Invalid or corrupted zip file."
        return 1
    fi

    local TMPDIR_RESTORE
    TMPDIR_RESTORE=$(mktemp -d)
    _BRCS_TEMPFILES+=("$TMPDIR_RESTORE")
    unzip -o "$backup_file" -d "$TMPDIR_RESTORE" >/dev/null

    collect_files "$TMPDIR_RESTORE"
    local files=("${_collected_files[@]}")
    local total=${#files[@]}
    local count=0

    stoa_paths_init
    local pre_restore_backup="$STOA_BACKUP_DIR/pre_restore_$(date +%Y%m%d_%H%M%S).zip"
    local existing_targets=()
    for FILE in "${files[@]}"; do
        local DEST="/${FILE#"$TMPDIR_RESTORE"/}"
        [ -f "$DEST" ] && existing_targets+=("$DEST")
    done
    if [ ${#existing_targets[@]} -gt 0 ] && command -v zip >/dev/null 2>&1; then
        log_msg INFO "Creating safety backup: $pre_restore_backup"
        zip -q "$pre_restore_backup" "${existing_targets[@]}" 2>/dev/null || true
    fi

    log_msg INFO "Restoring files (interactive)..."
    for FILE in "${files[@]}"; do
        DEST="/${FILE#"$TMPDIR_RESTORE"/}"

        if [ -f "$DEST" ]; then
            echo -e "  ${S}--- Changes for $DEST ---${R}"
            diff --color=auto "$DEST" "$FILE" 2>/dev/null && echo -e "  ${S}(no changes)${R}" || true
            echo -e "  ${S}---${R}"
        else
            echo -e "  ${B}--- New file: $DEST ---${R}"
        fi

        echo -e "  ${F}Restore $DEST? [y/N]${R}"
        read -r CONF
        if [[ "$CONF" =~ ^[Yy]$ ]]; then
            sudo mkdir -p "$(dirname "$DEST")"
            sudo cp "$FILE" "$DEST"
            log_msg INFO "Restored: $DEST"
        else
            log_msg INFO "Skipped: $DEST"
        fi
        count=$((count+1))
        progress_bar "$total" "$count"
    done
    rm -rf "$TMPDIR_RESTORE"
    log_msg INFO "Restore complete."
}

# ── Restore all (no prompt) ──

restore_all() {
    check_root

    local backup_file="${1:-}"
    [ -z "$backup_file" ] && read -r -p "  Enter the path to the backup file (.zip): " backup_file
    [ ! -f "$backup_file" ] && log_msg ERROR "File not found." && return 1

    if ! command -v unzip >/dev/null 2>&1; then
        log_msg ERROR "'unzip' is not installed. Please install it first."
        return 1
    fi

    if ! unzip -t "$backup_file" >/dev/null 2>&1; then
        log_msg ERROR "Invalid or corrupted zip file."
        return 1
    fi

    local TMPDIR_RESTORE
    TMPDIR_RESTORE=$(mktemp -d)
    _BRCS_TEMPFILES+=("$TMPDIR_RESTORE")
    unzip -o "$backup_file" -d "$TMPDIR_RESTORE" >/dev/null

    collect_files "$TMPDIR_RESTORE"
    local files=("${_collected_files[@]}")
    local total=${#files[@]}
    local count=0

    stoa_paths_init
    local pre_restore_backup="$STOA_BACKUP_DIR/pre_restore_$(date +%Y%m%d_%H%M%S).zip"
    local existing_targets=()
    for FILE in "${files[@]}"; do
        local DEST="/${FILE#"$TMPDIR_RESTORE"/}"
        [ -f "$DEST" ] && existing_targets+=("$DEST")
    done
    if [ ${#existing_targets[@]} -gt 0 ] && command -v zip >/dev/null 2>&1; then
        log_msg INFO "Creating safety backup: $pre_restore_backup"
        zip -q "$pre_restore_backup" "${existing_targets[@]}" 2>/dev/null || true
    fi

    log_msg INFO "Restoring all files..."
    for FILE in "${files[@]}"; do
        DEST="/${FILE#"$TMPDIR_RESTORE"/}"
        sudo mkdir -p "$(dirname "$DEST")"
        sudo cp "$FILE" "$DEST"
        log_msg INFO "Restored: $DEST"
        count=$((count+1))
        progress_bar "$total" "$count"
    done
    rm -rf "$TMPDIR_RESTORE"
    log_msg INFO "Full restore complete."
}

# ── Package manager wrappers ──

pkg_update() {
    case "$PKG_MANAGER" in
        apt)    run_cmd sudo apt-get update && run_cmd sudo apt-get upgrade -y ;;
        dnf)    run_cmd sudo dnf upgrade --refresh -y ;;
        yum)    run_cmd sudo yum update -y ;;
        pacman) run_cmd sudo pacman -Syu --noconfirm ;;
        zypper) run_cmd sudo zypper refresh && run_cmd sudo zypper update -y ;;
        apk)    run_cmd sudo apk update && run_cmd sudo apk upgrade ;;
        *)      log_msg WARN "Unknown package manager, skipping update." ;;
    esac
}

pkg_clean() {
    case "$PKG_MANAGER" in
        apt)
            run_cmd sudo apt-get clean
            run_cmd sudo apt-get autoclean
            ;;
        dnf)    run_cmd sudo dnf clean all ;;
        yum)    run_cmd sudo yum clean all ;;
        pacman)
            if command -v paccache >/dev/null 2>&1; then
                run_cmd sudo paccache -rk1
            else
                run_cmd sudo pacman -Sc --noconfirm
            fi
            ;;
        zypper) run_cmd sudo zypper clean --all ;;
        apk)    run_cmd sudo apk cache clean 2>/dev/null ;;
        *)      log_msg WARN "Unknown package manager, skipping clean." ;;
    esac
}

pkg_autoremove() {
    case "$PKG_MANAGER" in
        apt)
            run_cmd sudo apt-get autoremove -y
            if command -v deborphan >/dev/null 2>&1; then
                # run_cmd is a shell function, so it cannot be exec'd by
                # xargs — collect the names and pass them as arguments.
                local orphaned
                mapfile -t orphaned < <(deborphan 2>/dev/null)
                [ "${#orphaned[@]}" -gt 0 ] && \
                    run_cmd sudo apt-get -y remove --purge "${orphaned[@]}"
                mapfile -t orphaned < <(deborphan --guess-data 2>/dev/null)
                [ "${#orphaned[@]}" -gt 0 ] && \
                    run_cmd sudo apt-get -y remove --purge "${orphaned[@]}"
            fi
            if command -v localepurge >/dev/null 2>&1; then
                run_cmd sudo localepurge
            fi
            ;;
        dnf)    run_cmd sudo dnf autoremove -y ;;
        yum)    run_cmd sudo yum autoremove -y 2>/dev/null || run_cmd sudo package-cleanup --leaves -y 2>/dev/null ;;
        pacman)
            local orphans
            orphans=$(pacman -Qdtq 2>/dev/null)
            if [ -n "$orphans" ]; then
                echo "$orphans" | run_cmd sudo pacman -Rns --noconfirm - 2>/dev/null
            fi
            ;;
        zypper)
            local unneeded
            mapfile -t unneeded < <(zypper packages --unneeded 2>/dev/null \
                | awk -F'|' 'NR>4 {gsub(/ /, "", $3); if ($3 != "") print $3}')
            [ "${#unneeded[@]}" -gt 0 ] && run_cmd sudo zypper remove -y "${unneeded[@]}"
            ;;
        apk)    : ;;
        *)      log_msg WARN "Unknown package manager, skipping autoremove." ;;
    esac
}

# ── Full cleanup ──

full_cleanup() {
    check_root || return 1
    log_msg INFO "Starting ${CLEANUP_SCOPE} cleanup..."

    local space_before
    space_before=$(get_disk_used_kb)

    local steps
    if [ "$CLEANUP_SCOPE" = "safe" ]; then
        steps=("clean" "flatpak" "journal" "stoa" "tmp")
    else
        steps=("update" "clean" "autoremove" "snap" "flatpak" "journal" "kernels" "docker" "steam" "stoa" "tmp")
    fi
    local total=${#steps[@]}
    local count=0

    if _step update; then
        pkg_update
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step clean; then
        pkg_clean
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step autoremove; then
        pkg_autoremove
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step snap; then
      if command -v snap >/dev/null 2>&1; then
        run_cmd sudo snap set system refresh.retain=2 2>/dev/null
        if [ "$DRY_RUN" -eq 0 ]; then
            snap list --all 2>/dev/null | awk '/disabled/{print $1, $2}' | while read -r snapname revision; do
                sudo snap remove "$snapname" --revision="$revision" --purge 2>/dev/null || \
                sudo snap remove "$snapname" --purge 2>/dev/null
            done
        else
            log_msg INFO "[DRY-RUN] Would clean disabled snap revisions"
        fi
      fi
      count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step flatpak; then
        command -v flatpak >/dev/null 2>&1 && \
            run_cmd flatpak uninstall --unused -y 2>/dev/null
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step journal; then
        if command -v journalctl >/dev/null 2>&1; then
            run_cmd sudo journalctl --vacuum-time=7d 2>/dev/null
            run_cmd sudo journalctl --vacuum-size=100M 2>/dev/null
        fi
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step kernels && [ "$PKG_MANAGER" = "apt" ]; then
        local current_kernel
        current_kernel=$(uname -r)
        if [ "$DRY_RUN" -eq 0 ]; then
            dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -v "$current_kernel" | grep -v 'linux-image-generic' | while read -r pkg; do
                sudo apt-get remove -y "$pkg" 2>/dev/null
            done
        else
            local old_kernels
            old_kernels=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -v "$current_kernel" | grep -v 'linux-image-generic')
            [ -n "$old_kernels" ] && log_msg INFO "[DRY-RUN] Would remove old kernels: $old_kernels"
        fi
    elif _step kernels && [ "$PKG_MANAGER" = "dnf" ]; then
        run_cmd sudo dnf remove --oldinstallonly -y 2>/dev/null
    fi
    _step kernels && { count=$((count+1)); progress_bar "$total" "$count"; }

    if _step docker; then
        command -v docker >/dev/null 2>&1 && \
            run_cmd docker system prune -f 2>/dev/null
        count=$((count+1)); progress_bar "$total" "$count"
    fi

    if _step steam; then
      if [ -d "$HOME/.steam/steam/steamapps" ]; then
        # shadercache only. compatdata next to it holds the Proton
        # prefixes — a game's saves live there unless it uses Steam Cloud,
        # so it is not cache and is never deleted here.
        if [ "$DRY_RUN" -eq 0 ]; then
            rm -rf "$HOME/.steam/steam/steamapps/shadercache/"* 2>/dev/null
        else
            log_msg INFO "[DRY-RUN] Would clean the Steam shader cache"
        fi
      fi
      count=$((count+1)); progress_bar "$total" "$count"
    fi

    # Leftovers: our own archives, and the .bak/.log debris that any tool
    # leaves behind. Everything here is age-gated at 30 days except the
    # archive pruning, which is count-gated — a file nothing has written to
    # in a month is not in use by anything, which is what makes sweeping
    # *.log safe at all.
    #
    # Deliberately NOT touched: /var/log. Those belong to services that
    # hold them open, and the journal has its own step above.
    if _step stoa; then
        local pruned=0 swept=0 f
        [ "$DRY_RUN" -eq 0 ] && stoa_paths_init

        # Keep the two most recent of each archive kind; older ones are
        # superseded by definition — the newest is what you would restore.
        local pattern old
        for pattern in '*.confs.*.zip' 'pre_restore_*.zip'; do
            while IFS= read -r old; do
                [ -n "$old" ] || continue
                if [ "$DRY_RUN" -eq 0 ]; then rm -f "$old" 2>/dev/null; fi
                pruned=$((pruned + 1))
            done < <(find "$STOA_BACKUP_DIR" -maxdepth 1 -type f -name "$pattern" \
                        -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +3 \
                        | cut -d' ' -f2-)
        done

        # $HOME's top level: a stray .log or .bak there is debris, never a
        # program's working file. ~/.cache is debris by definition. Under
        # ~/.config and ~/.local/share only .bak is swept — a .log there
        # may well be an application's real log.
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if [ "$DRY_RUN" -eq 0 ]; then rm -f "$f" 2>/dev/null; fi
            swept=$((swept + 1))
        done < <(
            {
                find "$USER_DIR" -maxdepth 1 -type f \
                    \( -name '*.log' -o -name '*.bak' -o -name '*.bak.*' \) -mtime +30
                find "$USER_DIR/.cache" "$STOA_LOG_DIR" -type f \
                    \( -name '*.log' -o -name '*.bak' -o -name '*.bak.*' \) -mtime +30
                find "$USER_DIR/.config" "$USER_DIR/.local/share" -type f \
                    \( -name '*.bak' -o -name '*.bak.*' \) -mtime +30
            } 2>/dev/null
        )

        if [ "$DRY_RUN" -eq 0 ]; then
            log_msg INFO "Leftovers: pruned ${pruned} old archive(s), swept ${swept} stale .log/.bak"
        else
            log_msg INFO "[DRY-RUN] Would prune ${pruned} old archive(s) and sweep ${swept} stale .log/.bak"
        fi
        count=$((count + 1)); progress_bar "$total" "$count"
    fi

    log_msg INFO "Cleaning temporary files in /tmp and /var/tmp..."
    if [ "$DRY_RUN" -eq 0 ]; then
        collect_files "/tmp"
        local tmp1=("${_collected_files[@]}")
        collect_files "/var/tmp"
        local tmp2=("${_collected_files[@]}")
        local tmp_files=("${tmp1[@]}" "${tmp2[@]}")
        local total_tmp=${#tmp_files[@]}

        for file in "${tmp_files[@]}"; do
            if command -v lsof >/dev/null 2>&1; then
                lsof "$file" >/dev/null 2>&1 || rm -f "$file" 2>/dev/null
            elif command -v fuser >/dev/null 2>&1; then
                fuser "$file" >/dev/null 2>&1 || rm -f "$file" 2>/dev/null
            else
                rm -f "$file" 2>/dev/null
            fi
        done
        [ "$total_tmp" -gt 0 ] && progress_bar "$total_tmp" "$total_tmp"
    else
        log_msg INFO "[DRY-RUN] Would clean temporary files in /tmp and /var/tmp"
    fi
    count=$((count+1)); progress_bar "$total" "$count"

    local space_after freed_kb
    space_after=$(get_disk_used_kb)
    freed_kb=$((space_before - space_after))
    if [ "$freed_kb" -gt 0 ] 2>/dev/null; then
        if command -v numfmt >/dev/null 2>&1; then
            log_msg INFO "Disk space freed: $(numfmt --to=iec --suffix=B $((freed_kb * 1024)))"
        else
            log_msg INFO "Disk space freed: ${freed_kb} KB"
        fi
    else
        log_msg INFO "Cleanup complete (no measurable space freed or running in dry-run mode)."
    fi

    log_msg INFO "${CLEANUP_SCOPE^} cleanup completed."
}

# ── Schedule cleanup at boot ──

schedule_cleanup() {
    log_msg INFO "Scheduling cleanup at boot..."
    local script_path
    script_path="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

    # systemd first, deliberately. The cleanup runs pacman, paccache and
    # journalctl: it needs root. A @reboot line in *this user's* crontab
    # would run it unprivileged with no terminal, so each sudo inside would
    # fail as a PAM "conversation failed" and pam_faillock would lock the
    # account for ten minutes — locking you out of your own login screen on
    # every boot. The systemd unit runs as root, so nothing has to ask.
    _unschedule_user_crontab
    if command -v systemctl >/dev/null 2>&1; then
        local unit_dir="/etc/systemd/system"
        check_root || return 1

        sudo tee "$unit_dir/stoa-maintain-cleanup.service" >/dev/null <<SVCEOF
[Unit]
Description=Stoa Maintain system cleanup at boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $script_path --cleanup --unattended
SVCEOF

        sudo tee "$unit_dir/stoa-maintain-cleanup.timer" >/dev/null <<TMREOF
[Unit]
Description=Run Stoa Maintain cleanup on boot

[Timer]
OnBootSec=2min

[Install]
WantedBy=timers.target
TMREOF

        sudo systemctl daemon-reload
        sudo systemctl enable stoa-maintain-cleanup.timer
        log_msg INFO "Cleanup scheduled at boot via systemd timer."
    elif command -v crontab >/dev/null 2>&1; then
        # No systemd: root's crontab, so the job is already privileged.
        local CRON_CMD="@reboot bash $script_path --cleanup --unattended"
        (sudo crontab -l 2>/dev/null | grep -v "stoa-maintain" ; echo "$CRON_CMD") \
            | sudo crontab -
        log_msg INFO "Cleanup scheduled at boot via root crontab."
    else
        log_msg ERROR "Neither systemctl nor crontab found. Cannot schedule cleanup."
        return 1
    fi
}

# Older releases scheduled the cleanup in the *user's* crontab, where it
# could never authenticate. Drop that entry wherever it is still installed.
#
# Matching on the literal string "stoa-maintain" was not enough: this
# script is derived from BRCS.sh, which shipped the same @reboot line
# naming *its own* path. A crontab carrying
#   @reboot bash ~/StoaLinux/scripts/vendor/brcs/BRCS.sh --cleanup
# is the same defect under a different filename, and grepping for
# "stoa-maintain" walked straight past it — confirmed on a real machine,
# where nine sudo calls per boot kept the login screen locked. Match the
# whole family.
_LEGACY_CRON_RE='stoa-maintain|BRCS\.sh|brcs-cleanup'

_unschedule_user_crontab() {
    command -v crontab >/dev/null 2>&1 || return 0
    crontab -l 2>/dev/null | grep -qE "$_LEGACY_CRON_RE" || return 0
    crontab -l 2>/dev/null | grep -vE "$_LEGACY_CRON_RE" | crontab -
    log_msg INFO "Removed the legacy user-crontab cleanup entry (it could not authenticate)."
}

# ── Skip menu when sourced ──
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return

# Register signal trap
trap _brcs_cleanup EXIT INT TERM HUP

# ── CLI argument parser ──

show_help() {
    echo ""
    echo -e "  ${B}stoa-maintain${R} v${VERSION} — Backup · Restore · Cleanup · Schedule"
    echo ""
    echo -e "  ${F}Usage:${R} stoa-maintain [OPTION]"
    echo -e "         stoa-maintain            ${S}opens the interactive menu${R}"
    echo ""

    echo -e "  ${B}BACKUP${R}"
    echo -e "    ${F}--backup${R}"
    echo -e "${S}        Collects how this machine is set up into${R}"
    echo -e "${S}        ~/.local/state/stoa/backups/<host>.confs.<date>.zip, with${R}"
    echo -e "${S}        the log under ~/.local/state/stoa/logs/. Anything an older${R}"
    echo -e "${S}        release left at the top of \$HOME is moved there on first${R}"
    echo -e "${S}        run.${R}"
    echo -e "${S}        Takes /etc (*.conf, *.ini, *.rules), the package manager's${R}"
    echo -e "${S}        repo config, the usual dotfiles, ~/.config three levels${R}"
    echo -e "${S}        deep, your crontab, systemd units and network profiles.${R}"
    echo -e "${S}        Your documents are not in it — this is configuration${R}"
    echo -e "${S}        only, not a data backup.${R}"
    echo ""

    echo -e "  ${B}RESTORE${R}"
    echo -e "    ${F}--restore FILE${R}"
    echo -e "${S}        Writes every file in FILE back where it came from, without${R}"
    echo -e "${S}        asking. Saves what it is about to overwrite first, to${R}"
    echo -e "${S}        ~/.local/state/stoa/backups/pre_restore_<timestamp>.zip.${R}"
    echo ""
    echo -e "    ${F}--restore-interactive FILE${R}"
    echo -e "${S}        The same, one file at a time: shows a coloured diff between${R}"
    echo -e "${S}        disk and backup and asks before each. Use this to pull a${R}"
    echo -e "${S}        single config out of an old archive.${R}"
    echo ""
    echo -e "    ${F}--list FILE${R}"
    echo -e "${S}        Verifies the archive and prints what is inside. Changes${R}"
    echo -e "${S}        nothing.${R}"
    echo ""

    echo -e "  ${B}CLEANUP${R}"
    echo -e "    ${F}--cleanup${R}"
    echo -e "${S}        Eleven steps, reporting the space freed at the end:${R}"
    echo -e "${S}          1  upgrade every package${R}         ${T}changes what is installed${R}"
    echo -e "${S}          2  trim the package cache to one version per package${R}"
    echo -e "${S}          3  remove orphaned packages${R}       ${T}changes what is installed${R}"
    echo -e "${S}          4  drop disabled snap revisions${R}"
    echo -e "${S}          5  uninstall unused flatpak runtimes${R}"
    echo -e "${S}          6  vacuum the journal to 7 days / 100M${R}"
    echo -e "${S}          7  remove old kernels${R}             ${T}apt and dnf only${R}"
    echo -e "${S}          8  docker system prune${R}            ${T}drops stopped containers${R}"
    echo -e "${S}          9  clear the Steam shader cache${R}"
    echo -e "${S}         10  leftovers: keep the 2 newest archives of each kind,${R}"
    echo -e "${S}             and sweep, over 30 days old, .log/.bak at the top${R}"
    echo -e "${S}             of \$HOME and in ~/.cache, plus .bak under${R}"
    echo -e "${S}             ~/.config and ~/.local/share. Never /var/log.${R}"
    echo -e "${S}         11  clear /tmp and /var/tmp, skipping files in use${R}"
    echo -e "${S}        compatdata is never touched: Proton keeps game saves there.${R}"
    echo -e "${S}        Run this when you can watch it.${R}"
    echo ""
    echo -e "    ${F}--cleanup --unattended${R}"
    echo -e "${S}        Only steps 2, 5, 6, 10 and 11 — delete garbage, change${R}"
    echo -e "${S}        nothing else. No upgrade, no package removal, no Steam.${R}"
    echo -e "${S}        This is what the scheduled boot job runs.${R}"
    echo ""
    echo -e "    ${F}--dry-run${R}"
    echo -e "${S}        Use with --cleanup. Prints each command it would run${R}"
    echo -e "${S}        instead of running it.${R}"
    echo ""

    echo -e "  ${B}SCHEDULE${R}"
    echo -e "    ${F}--schedule${R}"
    echo -e "${S}        Runs the unattended cleanup two minutes after each boot,${R}"
    echo -e "${S}        as a systemd timer owned by root — it needs root, and a${R}"
    echo -e "${S}        job that has to ask for a password at boot has nobody to${R}"
    echo -e "${S}        ask. To undo:${R}"
    echo -e "${S}          sudo systemctl disable --now stoa-maintain-cleanup.timer${R}"
    echo -e "${S}        or Super+S → Maintenance → Schedule Cleanup at Boot.${R}"
    echo ""

    echo -e "    ${F}--help, -h${R}   ${S}this text${R}"
    echo ""
    echo -e "  ${S}Package manager detected:${R} ${B}${PKG_MANAGER}${R}"
    echo ""
}

ACTION=""
CLI_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --backup)               ACTION="backup"; shift ;;
        --restore)              ACTION="restore"; CLI_FILE="${2:-}"; shift; [ -n "$CLI_FILE" ] && shift ;;
        --restore-interactive)  ACTION="restore_interactive"; CLI_FILE="${2:-}"; shift; [ -n "$CLI_FILE" ] && shift ;;
        --cleanup)              ACTION="cleanup"; shift ;;
        --list)                 ACTION="list"; CLI_FILE="${2:-}"; shift; [ -n "$CLI_FILE" ] && shift ;;
        --schedule)             ACTION="schedule"; shift ;;
        --dry-run)              DRY_RUN=1; shift ;;
        --unattended)           CLEANUP_SCOPE="safe"; shift ;;
        --help|-h)              show_help; exit 0 ;;
        *)
            echo -e "  ${T}Unknown option: $1${R}"
            show_help
            exit 1
            ;;
    esac
done

# One-time housekeeping, after the parser so --dry-run stays a preview:
# it must not move anything either.
[ "$DRY_RUN" -eq 0 ] && stoa_paths_migrate

case "$ACTION" in
    backup)
        backup_configs
        exit $?
        ;;
    restore)
        [ -z "$CLI_FILE" ] && { log_msg ERROR "No file specified for --restore"; show_help; exit 1; }
        restore_all "$CLI_FILE"
        exit $?
        ;;
    restore_interactive)
        [ -z "$CLI_FILE" ] && { log_msg ERROR "No file specified for --restore-interactive"; show_help; exit 1; }
        restore_interactive "$CLI_FILE"
        exit $?
        ;;
    cleanup)
        full_cleanup
        exit $?
        ;;
    list)
        [ -z "$CLI_FILE" ] && { log_msg ERROR "No file specified for --list"; show_help; exit 1; }
        list_backup_contents "$CLI_FILE"
        exit $?
        ;;
    schedule)
        schedule_cleanup
        exit $?
        ;;
esac

# ── Interactive Menu ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA MAINTAIN — System Maintenance                  ║${R}"
echo -e "  ${B}║     Backup · Restore · Cleanup · Schedule               ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════════╝${R}"
echo ""

while true; do
    echo -e "  ${F}═══ Maintenance v${VERSION} ═══${R}"
    echo -e "  ${S}1)${F} Backup configurations${R}"
    echo -e "  ${S}2)${F} Restore configurations${R}"
    echo -e "  ${S}3)${F} Full system cleanup${R}"
    echo -e "  ${S}4)${F} Full system cleanup (dry-run)${R}"
    echo -e "  ${S}5)${F} List backup contents${R}"
    echo -e "  ${S}6)${F} Schedule cleanup at boot${R}"
    echo -e "  ${S}7)${F} Exit${R}"
    echo -e "  ${S}Package manager: ${B}$PKG_MANAGER${R}"
    echo ""
    read -r -p "  Choose an option: " option

    case "$option" in
        1) backup_configs ;;
        2)
            echo ""
            echo -e "  ${F}═══ Restore Options ═══${R}"
            echo -e "  ${S}1)${F} Interactive restore (review each file)${R}"
            echo -e "  ${S}2)${F} Restore all (no prompt)${R}"
            echo -e "  ${S}3)${F} Back${R}"
            read -r -p "  Choose an option: " restopt
            case "$restopt" in
                1) restore_interactive ;;
                2) restore_all ;;
                *) echo -e "  ${S}Returning...${R}" ;;
            esac
            ;;
        3) DRY_RUN=0; full_cleanup ;;
        4) DRY_RUN=1; full_cleanup; DRY_RUN=0 ;;
        5) list_backup_contents ;;
        6) schedule_cleanup ;;
        7) echo -e "  ${O}\"The wise man prepares.\" — Seneca${R}"; exit 0 ;;
        *) log_msg ERROR "Invalid option." ;;
    esac
done
