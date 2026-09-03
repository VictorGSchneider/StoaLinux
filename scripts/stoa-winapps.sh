#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — WinApps                                      ║
# ║  "We suffer more in imagination than in reality." — Seneca  ║
# ║                                                              ║
# ║  Run Windows applications seamlessly on Linux via            ║
# ║  KVM/QEMU + FreeRDP. Separate yad menu.                     ║
# ╚══════════════════════════════════════════════════════════════╝

WINAPPS_DIR="${HOME}/.config/winapps"
WINAPPS_CONF="${WINAPPS_DIR}/winapps.conf"
WINAPPS_APPS_DIR="${WINAPPS_DIR}/apps"
VM_NAME="StoaWindows"

# ── Helpers ──

_notify() { notify-send -t 2500 "Stoa WinApps" "$1" 2>/dev/null; }

_yad_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" \
        | yad --list --title="$prompt" --column="Option" --no-headers \
              --width=460 --height=420 --separator=''
}

_yad_input() {
    local prompt="$1"
    local hide="${2:-}"
    if [ "$hide" = "hide" ]; then
        yad --entry --title="$prompt" --width=380 --hide-text
    else
        yad --entry --title="$prompt" --width=380
    fi
}

_yad_confirm() {
    local msg="$1"
    yad --question --title="Stoa WinApps" --text="$msg"
}

_check_deps() {
    local missing=()
    command -v virsh   &>/dev/null || missing+=(libvirt)
    command -v qemu-system-x86_64 &>/dev/null || missing+=(qemu)
    command -v xfreerdp &>/dev/null || missing+=(freerdp)
    command -v virt-manager &>/dev/null || missing+=(virt-manager)

    if [ ${#missing[@]} -gt 0 ]; then
        _notify "Missing: ${missing[*]}\nInstall via Stoa Store (Super+A)"
        return 1
    fi
    return 0
}

_vm_running() {
    virsh list --name 2>/dev/null | grep -q "^${VM_NAME}$"
}

_vm_exists() {
    virsh list --all --name 2>/dev/null | grep -q "^${VM_NAME}$"
}

_ensure_config() {
    mkdir -p "$WINAPPS_DIR" "$WINAPPS_APPS_DIR"
    if [ ! -f "$WINAPPS_CONF" ]; then
        cat > "$WINAPPS_CONF" <<'EOF'
# WinApps configuration
# RDP connection settings for the Windows VM
RDP_USER="User"
RDP_PASS=""
RDP_IP="192.168.122.2"
RDP_PORT="3389"
RDP_FLAGS="/dynamic-resolution /sound:sys:pulse /microphone:sys:pulse"
VM_NAME="StoaWindows"
MULTIMON="false"
EOF
        _notify "Config created at ${WINAPPS_CONF}\nPlease configure RDP credentials."
    fi
    # shellcheck source=/dev/null
    source "$WINAPPS_CONF"
}

# ══════════════════════════════════════════════════════════════
#   VM MANAGEMENT
# ══════════════════════════════════════════════════════════════

_vm_panel() {
    while true; do
        local status="Stopped"
        _vm_running && status="Running"

        local choice
        choice=$(_yad_select "  VM (${status})" \
            "  Start VM" \
            "  Stop VM" \
            "  Restart VM" \
            "  Pause / Resume" \
            "  Open virt-manager" \
            "  VM Info" \
            "  Create VM (guided)" \
            "  Back")

        case "$choice" in
            *"Start VM"*)
                if _vm_exists; then
                    virsh start "$VM_NAME" 2>/dev/null
                    _notify "Starting ${VM_NAME}..."
                    # Wait for VM to boot and RDP to be ready
                    local i=0
                    while [ $i -lt 30 ]; do
                        if xfreerdp /v:"${RDP_IP}:${RDP_PORT}" /cert:ignore +auth-only /u:"${RDP_USER}" /p:"${RDP_PASS}" 2>/dev/null; then
                            _notify "VM ready!"
                            break
                        fi
                        sleep 2
                        i=$((i + 1))
                    done
                else
                    _notify "No VM found. Use 'Create VM' first."
                fi
                ;;
            *"Stop VM"*)
                if _vm_running; then
                    if _yad_confirm "Shutdown ${VM_NAME}?"; then
                        virsh shutdown "$VM_NAME" 2>/dev/null
                        _notify "Shutting down ${VM_NAME}..."
                    fi
                else
                    _notify "VM is not running."
                fi
                ;;
            *"Restart VM"*)
                if _vm_running; then
                    virsh reboot "$VM_NAME" 2>/dev/null
                    _notify "Rebooting ${VM_NAME}..."
                fi
                ;;
            *"Pause"*)
                if _vm_running; then
                    local state
                    state=$(virsh domstate "$VM_NAME" 2>/dev/null)
                    if [ "$state" = "paused" ]; then
                        virsh resume "$VM_NAME" 2>/dev/null
                        _notify "VM resumed."
                    else
                        virsh suspend "$VM_NAME" 2>/dev/null
                        _notify "VM paused."
                    fi
                fi
                ;;
            *"virt-manager"*)
                virt-manager &
                ;;
            *"VM Info"*)
                if _vm_exists; then
                    local info
                    info=$(virsh dominfo "$VM_NAME" 2>/dev/null)
                    local mem cpu state
                    state=$(echo "$info" | awk '/^State:/ {$1=""; print $0}' | xargs)
                    mem=$(echo "$info" | awk '/^Max memory:/ {printf "%.0f GB", $3/1048576}')
                    cpu=$(echo "$info" | awk '/^CPU\(s\):/ {print $2}')
                    _yad_select "  VM Info" \
                        "  State: ${state}" \
                        "  Memory: ${mem}" \
                        "  CPUs: ${cpu}" \
                        "  Name: ${VM_NAME}" \
                        "  Back"
                else
                    _notify "No VM found."
                fi
                ;;
            *"Create VM"*)
                _create_vm
                ;;
            *"Back"*|"") break ;;
        esac
    done
}

_create_vm() {
    _notify "Opening virt-manager for VM creation.\n\nRecommended:\n• Name: ${VM_NAME}\n• RAM: 4+ GB\n• Disk: 40+ GB\n• Enable RDP in Windows after install."
    virt-manager &
}

# ══════════════════════════════════════════════════════════════
#   RDP CONNECTION
# ══════════════════════════════════════════════════════════════

_rdp_connect() {
    local app="$1"

    if ! _vm_running; then
        if _yad_confirm "VM is off. Start it?"; then
            virsh start "$VM_NAME" 2>/dev/null
            _notify "Starting VM... please wait."
            sleep 10
        else
            return
        fi
    fi

    local -a cmd=(xfreerdp "/v:${RDP_IP}:${RDP_PORT}" "/u:${RDP_USER}" "/p:${RDP_PASS}" /cert:ignore)

    # Split RDP_FLAGS on spaces into array elements
    read -ra flags <<< "$RDP_FLAGS"
    cmd+=("${flags[@]}")

    if [ "$MULTIMON" = "true" ]; then
        cmd+=(/multimon)
    fi

    if [ -n "$app" ]; then
        cmd+=("/app:${app}")
    fi

    "${cmd[@]}" &
    disown
}

# ══════════════════════════════════════════════════════════════
#   APP MANAGEMENT
# ══════════════════════════════════════════════════════════════

_builtin_apps() {
    # Common Windows apps with their executable paths
    cat <<'EOF'
Microsoft Word|C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE
Microsoft Excel|C:\Program Files\Microsoft Office\root\Office16\EXCEL.EXE
Microsoft PowerPoint|C:\Program Files\Microsoft Office\root\Office16\POWERPNT.EXE
Microsoft Outlook|C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE
Microsoft OneNote|C:\Program Files\Microsoft Office\root\Office16\ONENOTE.EXE
Microsoft Access|C:\Program Files\Microsoft Office\root\Office16\MSACCESS.EXE
Microsoft Publisher|C:\Program Files\Microsoft Office\root\Office16\MSPUB.EXE
Internet Explorer|C:\Program Files\Internet Explorer\iexplore.exe
Notepad|C:\Windows\notepad.exe
Paint|C:\Windows\system32\mspaint.exe
Calculator|C:\Windows\system32\calc.exe
File Explorer|C:\Windows\explorer.exe
CMD|C:\Windows\system32\cmd.exe
PowerShell|C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
Task Manager|C:\Windows\system32\taskmgr.exe
Control Panel|C:\Windows\system32\control.exe
EOF
}

_custom_apps_list() {
    if [ -d "$WINAPPS_APPS_DIR" ]; then
        for f in "$WINAPPS_APPS_DIR"/*.conf; do
            [ -f "$f" ] || continue
            local name path
            name=$(grep '^NAME=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"')
            path=$(grep '^PATH=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"')
            [ -n "$name" ] && [ -n "$path" ] && echo "${name}|${path}"
        done
    fi
}

_launch_app() {
    local entries=()
    local paths=()

    # Built-in apps
    while IFS='|' read -r name path; do
        entries+=("  ${name}")
        paths+=("$path")
    done < <(_builtin_apps)

    # Custom apps
    while IFS='|' read -r name path; do
        entries+=("  ${name}")
        paths+=("$path")
    done < <(_custom_apps_list)

    entries+=("  Full Desktop (RDP)")
    entries+=("  Back")

    local choice
    choice=$(_yad_select "  Windows Apps" "${entries[@]}")

    case "$choice" in
        *"Full Desktop"*)
            _rdp_connect ""
            ;;
        *"Back"*|"") return ;;
        *)
            local i=0
            for entry in "${entries[@]}"; do
                if [ "$entry" = "$choice" ]; then
                    _rdp_connect "${paths[$i]}"
                    return
                fi
                i=$((i + 1))
            done
            ;;
    esac
}

_add_custom_app() {
    local name
    name=$(_yad_input "  App name")
    [ -z "$name" ] && return

    local path
    path=$(_yad_input "  EXE path (e.g. C:\\Program Files\\App\\app.exe)")
    [ -z "$path" ] && return

    mkdir -p "$WINAPPS_APPS_DIR"
    local slug
    slug=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
    cat > "${WINAPPS_APPS_DIR}/${slug}.conf" <<EOF
NAME="${name}"
PATH="${path}"
EOF
    _notify "Added: ${name}"
}

_remove_custom_app() {
    local entries=()
    local files=()

    for f in "$WINAPPS_APPS_DIR"/*.conf; do
        [ -f "$f" ] || continue
        local name
        name=$(grep '^NAME=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"')
        [ -n "$name" ] && entries+=("  ${name}") && files+=("$f")
    done

    if [ ${#entries[@]} -eq 0 ]; then
        _notify "No custom apps to remove."
        return
    fi

    entries+=("  Back")

    local choice
    choice=$(_yad_select "  Remove app" "${entries[@]}")

    case "$choice" in
        *"Back"*|"") return ;;
        *)
            local i=0
            for entry in "${entries[@]}"; do
                if [ "$entry" = "$choice" ]; then
                    local app_name
                    app_name=$(grep '^NAME=' "${files[$i]}" 2>/dev/null | cut -d= -f2- | tr -d '"')
                    if _yad_confirm "Remove ${app_name}?"; then
                        rm -f "${files[$i]}"
                        _notify "Removed: ${app_name}"
                    fi
                    return
                fi
                i=$((i + 1))
            done
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
#   CONFIGURATION
# ══════════════════════════════════════════════════════════════

_config_panel() {
    while true; do
        local choice
        choice=$(_yad_select "  WinApps Config" \
            "  RDP User: ${RDP_USER}" \
            "  RDP Password: ••••" \
            "  RDP IP: ${RDP_IP}" \
            "  RDP Port: ${RDP_PORT}" \
            "  VM Name: ${VM_NAME}" \
            "  Multi-Monitor: ${MULTIMON}" \
            "  Edit config file" \
            "  Test connection" \
            "  Back")

        case "$choice" in
            *"RDP User"*)
                local val
                val=$(_yad_input "  Username")
                [ -n "$val" ] && sed -i "s|^RDP_USER=.*|RDP_USER=\"${val}\"|" "$WINAPPS_CONF"
                RDP_USER="$val"
                ;;
            *"RDP Password"*)
                local val
                val=$(_yad_input "  Password" hide)
                [ -n "$val" ] && sed -i "s|^RDP_PASS=.*|RDP_PASS=\"${val}\"|" "$WINAPPS_CONF"
                RDP_PASS="$val"
                ;;
            *"RDP IP"*)
                local val
                val=$(_yad_input "  IP Address")
                [ -n "$val" ] && sed -i "s|^RDP_IP=.*|RDP_IP=\"${val}\"|" "$WINAPPS_CONF"
                RDP_IP="$val"
                ;;
            *"RDP Port"*)
                local val
                val=$(_yad_input "  Port")
                [ -n "$val" ] && sed -i "s|^RDP_PORT=.*|RDP_PORT=\"${val}\"|" "$WINAPPS_CONF"
                RDP_PORT="$val"
                ;;
            *"VM Name"*)
                local val
                val=$(_yad_input "  VM Name")
                [ -n "$val" ] && sed -i "s|^VM_NAME=.*|VM_NAME=\"${val}\"|" "$WINAPPS_CONF"
                VM_NAME="$val"
                ;;
            *"Multi-Monitor"*)
                if [ "$MULTIMON" = "true" ]; then
                    sed -i "s|^MULTIMON=.*|MULTIMON=\"false\"|" "$WINAPPS_CONF"
                    MULTIMON="false"
                else
                    sed -i "s|^MULTIMON=.*|MULTIMON=\"true\"|" "$WINAPPS_CONF"
                    MULTIMON="true"
                fi
                _notify "Multi-Monitor: ${MULTIMON}"
                ;;
            *"Edit config"*)
                if command -v nvim &>/dev/null; then
                    kitty -e nvim "$WINAPPS_CONF" &
                elif command -v vim &>/dev/null; then
                    kitty -e vim "$WINAPPS_CONF" &
                else
                    kitty -e nano "$WINAPPS_CONF" &
                fi
                ;;
            *"Test connection"*)
                _notify "Testing RDP connection..."
                if xfreerdp /v:"${RDP_IP}:${RDP_PORT}" /cert:ignore +auth-only /u:"${RDP_USER}" /p:"${RDP_PASS}" 2>/dev/null; then
                    _notify "Connection successful!"
                else
                    _notify "Connection failed.\nCheck VM is running and RDP is enabled."
                fi
                ;;
            *"Back"*|"") break ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   SERVICES
# ══════════════════════════════════════════════════════════════

_services_panel() {
    while true; do
        local libvirtd_status="inactive"
        systemctl is-active libvirtd &>/dev/null && libvirtd_status="active"

        local default_net="inactive"
        virsh net-info default 2>/dev/null | grep -q "Active:.*yes" && default_net="active"

        local choice
        choice=$(_yad_select "  Services" \
            "  libvirtd: ${libvirtd_status}" \
            "  Default network: ${default_net}" \
            "  Enable libvirtd on boot" \
            "  Add user to libvirt group" \
            "  Back")

        case "$choice" in
            *"libvirtd:"*)
                if [ "$libvirtd_status" = "active" ]; then
                    sudo systemctl stop libvirtd 2>/dev/null
                    _notify "libvirtd stopped."
                else
                    sudo systemctl start libvirtd 2>/dev/null
                    _notify "libvirtd started."
                fi
                ;;
            *"Default network"*)
                if [ "$default_net" = "active" ]; then
                    sudo virsh net-destroy default 2>/dev/null
                    _notify "Default network stopped."
                else
                    sudo virsh net-start default 2>/dev/null
                    _notify "Default network started."
                fi
                ;;
            *"Enable libvirtd"*)
                sudo systemctl enable libvirtd 2>/dev/null
                _notify "libvirtd enabled on boot."
                ;;
            *"Add user"*)
                sudo usermod -aG libvirt "$USER" 2>/dev/null
                sudo usermod -aG kvm "$USER" 2>/dev/null
                _notify "Added ${USER} to libvirt and kvm groups.\nLog out and back in for changes to take effect."
                ;;
            *"Back"*|"") break ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════

main() {
    _check_deps || return

    _ensure_config

    while true; do
        local vm_status="Off"
        _vm_running && vm_status="Running"

        local choice
        choice=$(_yad_select "  WinApps [VM: ${vm_status}]" \
            "  Launch Windows App" \
            "  Full Desktop (RDP)" \
            "  Add Custom App" \
            "  Remove Custom App" \
            "  VM Management" \
            "  Configuration" \
            "  Services (libvirt)" \
            "  Close")

        case "$choice" in
            *"Launch Windows App"*)
                _launch_app
                ;;
            *"Full Desktop"*)
                _rdp_connect ""
                ;;
            *"Add Custom App"*)
                _add_custom_app
                ;;
            *"Remove Custom App"*)
                _remove_custom_app
                ;;
            *"VM Management"*)
                _vm_panel
                ;;
            *"Configuration"*)
                _config_panel
                ;;
            *"Services"*)
                _services_panel
                ;;
            *"Close"*|"") break ;;
        esac
    done
}

main "$@"
