#!/bin/bash
# stoa-gpu-setup must notice every kernel that is not the stock `linux`.
#
# Its driver choice hangs on one question, spelled out in the script:
# the prebuilt NVIDIA package "only ships modules for the stock `linux`
# kernel; anything else MUST use the DKMS variant or the module won't build".
# needs_dkms answers it from detect_kernels — and detect_kernels only knows
# five names (linux, -zen, -lts, -hardened, -rt). CachyOS, the second distro
# on the README's first line, installs linux-cachyos: no match, an empty
# list, "no DKMS needed", and the script offers the non-DKMS `nvidia` target.
# On the CachyOS machine this was found on that name resolves to the legacy
# nvidia-580xx-dkms and collides with the linux-cachyos-nvidia-open modules
# already installed.
#
#   K1  only `linux` installed          → no DKMS (the prebuilt module fits)
#   K2  linux + linux-zen               → DKMS
#   K3  only linux-cachyos              → DKMS
#   K4  linux-cachyos + linux-cachyos-lts → DKMS
#   K5  packages that merely start with "linux" (firmware, headers,
#       api-headers) are not kernels    → no DKMS on their own
#
# The two functions are lifted out of the script and run against a stub
# pacman; nothing is installed and no hardware is probed.

cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

# pacman -Qq → the package list for this case, one name per line
printf '#!/bin/sh\n[ "$1" = "-Qq" ] && printf "%%s\\n" $FAKE_PKGS\nexit 0\n' > "$TMP/bin/pacman"
chmod +x "$TMP/bin/pacman"

{
    sed -n '/^detect_kernels() {/,/^}/p; /^needs_dkms() {/,/^}/p' scripts/system/stoa-gpu-setup.sh
    echo 'if needs_dkms; then echo dkms; else echo prebuilt; fi'
} > "$TMP/harness.sh"

_case() { # <installed packages…> → dkms | prebuilt
    FAKE_PKGS="$*" PATH="$TMP/bin:$PATH" bash "$TMP/harness.sh" 2>/dev/null
}
BASE="bash coreutils linux-firmware linux-api-headers"

_check "K1 stock linux only"              "prebuilt" "$(_case $BASE linux linux-headers)"
_check "K2 linux + linux-zen"             "dkms"     "$(_case $BASE linux linux-zen)"
_check "K3 linux-cachyos only"            "dkms"     "$(_case $BASE linux-cachyos linux-cachyos-headers)"
_check "K4 linux-cachyos + -lts"          "dkms"     "$(_case $BASE linux-cachyos linux-cachyos-lts)"
_check "K5 firmware and headers are not kernels" "prebuilt" "$(_case $BASE linux linux-headers linux-firmware-whence)"

# K9: the prebuilt module packages (linux-cachyos-nvidia-open) are named like
# kernels but are not: they have no -headers package, and the script asked
# pacman for linux-cachyos-nvidia-open-headers ("target not found").
_kernels() { { sed -n '/^detect_kernels() {/,/^}/p' scripts/system/stoa-gpu-setup.sh; echo detect_kernels; } > "$TMP/h3.sh"
             FAKE_PKGS="$*" PATH="$TMP/bin:$PATH" bash "$TMP/h3.sh" 2>/dev/null | tr '\n' ' '; }
_check "K9 module packages are not kernels" "linux-cachyos linux-cachyos-lts " \
    "$(_kernels $BASE linux-cachyos linux-cachyos-lts linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open linux-cachyos-headers)"

# K6-K8: never add a second provider of the NVIDIA kernel module. The package
# the script used to offer on CachyOS (nvidia → nvidia-580xx-dkms) conflicts
# with the prebuilt linux-cachyos-nvidia-open and the transaction is refused.
{
    sed -n '/^nvidia_module_installed() {/,/^}/p' scripts/system/stoa-gpu-setup.sh
    echo 'if nvidia_module_installed; then echo present; else echo absent; fi'
} > "$TMP/harness2.sh"
_mod() { FAKE_PKGS="$*" PATH="$TMP/bin:$PATH" bash "$TMP/harness2.sh" 2>/dev/null; }
_check "K6 prebuilt linux-cachyos-nvidia-open is seen" "present" "$(_mod $BASE linux-cachyos linux-cachyos-nvidia-open nvidia-utils)"
_check "K7 firmware and userspace alone are not a module" "absent" "$(_mod $BASE linux nvidia-utils linux-firmware-nvidia)"
_check "K8 a plain nvidia package is seen" "present" "$(_mod $BASE linux nvidia)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "gpu-setup-kernels: all checks passed"
