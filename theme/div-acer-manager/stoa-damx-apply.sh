#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Div Acer Manager Max Theme Installer          ║
# ║  Applies Stoa palette to DAMX (Avalonia app)                ║
# ║                                                              ║
# ║  Also patches MainWindow.axaml background + title gradient.  ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_THEME_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STOA_AXAML="${STOA_THEME_DIR}/stoa-damx.axaml"

# Common install locations for Div Acer Manager Max
DAMX_PATHS=(
    "/opt/div-acer-manager-max"
    "/opt/DivAcerManagerMax"
    "/usr/lib/div-acer-manager-max"
    "/usr/share/div-acer-manager-max"
    "${HOME}/.local/share/div-acer-manager-max"
    "${HOME}/.local/opt/DivAcerManagerMax"
)

_find_damx() {
    for path in "${DAMX_PATHS[@]}"; do
        if [ -f "$path/App.axaml" ]; then
            echo "$path"
            return
        fi
    done

    # Try to find via package manager
    local pkg_path
    pkg_path=$(pacman -Ql div-acer-manager-max 2>/dev/null | grep "App.axaml" | awk '{print $2}' | head -1)
    if [ -n "$pkg_path" ]; then
        dirname "$pkg_path"
        return
    fi

    # Try locate
    pkg_path=$(find /opt /usr -name "App.axaml" -path "*DivAcer*" 2>/dev/null | head -1)
    if [ -n "$pkg_path" ]; then
        dirname "$pkg_path"
        return
    fi

    echo ""
}

_apply_theme() {
    local damx_dir="$1"

    if [ ! -f "$damx_dir/App.axaml" ]; then
        echo "ERROR: App.axaml not found in $damx_dir"
        return 1
    fi

    echo "Applying Stoa theme to Div Acer Manager Max..."
    echo "  Directory: $damx_dir"

    # Backup original
    if [ ! -f "$damx_dir/App.axaml.original" ]; then
        echo "  Backing up App.axaml → App.axaml.original"
        sudo cp "$damx_dir/App.axaml" "$damx_dir/App.axaml.original"
    fi

    # Apply Stoa theme
    echo "  Applying stoa-damx.axaml → App.axaml"
    sudo cp "$STOA_AXAML" "$damx_dir/App.axaml"

    # Patch MainWindow.axaml background color
    if [ -f "$damx_dir/MainWindow.axaml" ]; then
        if [ ! -f "$damx_dir/MainWindow.axaml.original" ]; then
            sudo cp "$damx_dir/MainWindow.axaml" "$damx_dir/MainWindow.axaml.original"
        fi

        echo "  Patching MainWindow.axaml..."

        # Window background: #0e0e11 → #1a1714 (Stoa bg-dark)
        sudo sed -i 's/Background="#0e0e11"/Background="#1a1714"/g' "$damx_dir/MainWindow.axaml"

        # TabControl background: #18181b → #211e19 (Stoa bg)
        sudo sed -i 's/Background="#18181b"/Background="#211e19"/g' "$damx_dir/MainWindow.axaml"
        sudo sed -i 's/BorderBrush="#18181b"/BorderBrush="#211e19"/g' "$damx_dir/MainWindow.axaml"

        # Title gradient: blue → bronze
        sudo sed -i 's/#72bff4/#c49a5c/g' "$damx_dir/MainWindow.axaml"
        sudo sed -i 's/#3678c3/#a07a3c/g' "$damx_dir/MainWindow.axaml"
    fi

    echo ""
    echo "Done! Restart Div Acer Manager to see changes."
    echo "To restore: sudo cp $damx_dir/App.axaml.original $damx_dir/App.axaml"
}

_restore() {
    local damx_dir="$1"

    if [ -f "$damx_dir/App.axaml.original" ]; then
        sudo cp "$damx_dir/App.axaml.original" "$damx_dir/App.axaml"
        echo "Restored App.axaml from backup."
    fi

    if [ -f "$damx_dir/MainWindow.axaml.original" ]; then
        sudo cp "$damx_dir/MainWindow.axaml.original" "$damx_dir/MainWindow.axaml"
        echo "Restored MainWindow.axaml from backup."
    fi
}

# ── Main ──

case "${1:-}" in
    restore)
        DAMX_DIR=$(_find_damx)
        [ -z "$DAMX_DIR" ] && { echo "Div Acer Manager not found."; exit 1; }
        _restore "$DAMX_DIR"
        ;;
    apply|"")
        DAMX_DIR=$(_find_damx)
        if [ -z "$DAMX_DIR" ]; then
            echo "Div Acer Manager Max not found."
            echo ""
            echo "If installed in a custom location, run:"
            echo "  $0 /path/to/DivAcerManagerMax"
            exit 1
        fi
        _apply_theme "$DAMX_DIR"
        ;;
    *)
        # Custom path provided
        if [ -d "$1" ]; then
            _apply_theme "$1"
        else
            echo "Usage: $0 [apply|restore|/path/to/damx]"
            exit 1
        fi
        ;;
esac
