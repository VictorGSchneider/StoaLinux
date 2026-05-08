# Shared AUR install helpers for Stoa setup scripts.
# Sourced by setup/post-install.sh (local) and setup/arch-install.sh (chroot).
# Callers must define the color vars: B S F O T R.

_aur_fresh=0

# Local: install AUR pkg on the current system.
# Usage: _install_aur <pkg> <label> [<bin>]
# Pass <bin> to skip when the command already exists.
# Sets _aur_fresh=1 if newly installed, 0 if skipped.
_install_aur() {
    local pkg="$1" label="$2" bin="${3:-}"
    _aur_fresh=0
    echo ""
    if [ -n "$bin" ] && command -v "$bin" &>/dev/null; then
        echo -e "  ${S}[~] ${label} already installed.${R}"
        return 0
    fi
    echo -e "  ${F}Installing ${label} (AUR)...${R}"
    if command -v yay &>/dev/null; then
        yay -S --needed --noconfirm "$pkg"
    elif command -v paru &>/dev/null; then
        paru -S --needed --noconfirm "$pkg"
    else
        echo -e "  ${S}Installing ${label} manually via makepkg...${R}"
        local _tmpdir; _tmpdir=$(mktemp -d)
        git clone "https://aur.archlinux.org/${pkg}.git" "$_tmpdir/$pkg"
        (cd "$_tmpdir/$pkg" && makepkg -si --noconfirm)
        rm -rf "$_tmpdir"
    fi
    echo -e "  ${O}[✓] ${label} installed.${R}"
    _aur_fresh=1
}

# Chroot variant: install AUR pkg into a target system mounted at $INSTALL_ROOT
# as user $CREATED_USER (both must be set in the caller's env).
# Usage: _install_aur_chroot <pkg> <label>
_install_aur_chroot() {
    local pkg="$1" label="$2"
    echo -e "  ${F}Installing ${label} (AUR)...${R}"
    if arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
        "yay -S --needed --noconfirm $pkg" 2>/dev/null; then
        echo -e "  ${O}[✓] ${label} installed.${R}"
    else
        echo -e "  ${T}[!] ${label} install failed (continue manually after boot).${R}"
    fi
}
