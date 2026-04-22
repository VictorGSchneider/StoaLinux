#!/bin/bash
# Stoa Store — primary language package managers (pip, pipx, npm, cargo,
# gem, go, dotnet) + dispatcher for the rest (sourced from lang-misc.sh).

_lang_detect_available() {
    local items=()
    command -v pip      &>/dev/null && items+=("  Python (pip)")
    command -v pipx     &>/dev/null && items+=("  Python apps (pipx)")
    command -v npm      &>/dev/null && items+=("  Node.js (npm)")
    command -v yarn     &>/dev/null && items+=("  Node.js (yarn)")
    command -v pnpm     &>/dev/null && items+=("  Node.js (pnpm)")
    command -v cargo    &>/dev/null && items+=("  Rust (cargo)")
    command -v gem      &>/dev/null && items+=("  Ruby (gem)")
    command -v go       &>/dev/null && items+=("  Go (go install)")
    command -v composer &>/dev/null && items+=("  PHP (composer)")
    command -v dotnet   &>/dev/null && items+=("  .NET (dotnet/nuget)")
    command -v luarocks &>/dev/null && items+=("  Lua (luarocks)")
    command -v cpan     &>/dev/null && items+=("  Perl (cpan)")
    command -v ghcup    &>/dev/null && items+=("  Haskell (cabal/stack)")
    command -v julia    &>/dev/null && items+=("  Julia (Pkg)")
    command -v R        &>/dev/null && items+=("  R (CRAN)")
    printf '%s\n' "${items[@]}"
}

_lang_pip() {
    while true; do
        local count; count=$(pip list 2>/dev/null | tail -n +3 | wc -l)
        local choice; choice=$(_rofi_list "  Python pip ($count pkgs)" \
            "  Search PyPI" "  Installed packages" "  Outdated packages" \
            "  Install package" "  Uninstall package" "  Package info" \
            "  Show dependencies" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_rofi_input "  Search PyPI"); [ -z "$q" ] && continue
                _notify "Searching PyPI..."
                local r; r=$(pip index versions "$q" 2>/dev/null || pip search "$q" 2>/dev/null \
                    || echo "Use: pip install $q (PyPI search API may be disabled)")
                echo "$r" | _rofi "  PyPI: $q" ;;
            *"Installed packages"*)
                local pkgs; pkgs=$(pip list 2>/dev/null)
                [ -z "$pkgs" ] && { _notify "No pip packages"; continue; }
                local sel; sel=$(echo "$pkgs" | _rofi "  pip list")
                [ -z "$sel" ] && continue
                pip show "$(echo "$sel" | awk '{print $1}')" 2>/dev/null | _rofi "  pip" ;;
            *Outdated*)
                _notify "Checking outdated..."
                local out; out=$(pip list --outdated 2>/dev/null)
                [ -z "$out" ] && { _notify "All up to date"; continue; }
                local sel; sel=$(echo "$out" | _rofi "  pip outdated")
                [ -z "$sel" ] && continue
                local name; name=$(echo "$sel" | awk '{print $1}')
                _confirm "Upgrade $name?" && _run_in_term "pip install --upgrade $name" ;;
            *"Install package"*)
                local pkg; pkg=$(_rofi_input "  pip install")
                [ -n "$pkg" ] && _run_in_term "pip install $pkg" ;;
            *Uninstall*)
                local pkgs; pkgs=$(pip list --format=columns 2>/dev/null | tail -n +3)
                local sel; sel=$(echo "$pkgs" | _rofi "  pip uninstall")
                [ -z "$sel" ] && continue
                local name; name=$(echo "$sel" | awk '{print $1}')
                _confirm "Uninstall $name?" && _run_in_term "pip uninstall $name" ;;
            *"Package info"*)
                local pkg; pkg=$(_rofi_input "  pip show (package name)")
                [ -n "$pkg" ] && pip show "$pkg" 2>/dev/null | _rofi "  pip: $pkg" ;;
            *dependencies*)
                local pkg; pkg=$(_rofi_input "  Show deps for")
                [ -z "$pkg" ] && continue
                local info; info=$(pip show "$pkg" 2>/dev/null)
                local deps  rdeps
                deps=$(echo "$info"  | grep "^Requires:"    | sed 's/Requires: //')
                rdeps=$(echo "$info" | grep "^Required-by:" | sed 's/Required-by: //')
                printf '%s\n' "── $pkg depends on ──" "${deps:-  (none)}" "" \
                              "── Required by ──"     "${rdeps:-  (none)}" \
                    | _rofi "  pip deps: $pkg" ;;
        esac
    done
}

_lang_pipx() {
    while true; do
        local choice; choice=$(_rofi_list "  Python pipx" \
            "  Install app" "  Installed apps" "  Upgrade all" "  Uninstall app" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *"Install app"*)
                local pkg; pkg=$(_rofi_input "  pipx install")
                [ -n "$pkg" ] && _run_in_term "pipx install $pkg" ;;
            *Installed*)
                local apps; apps=$(pipx list --short 2>/dev/null)
                echo "${apps:-No apps installed}" | _rofi "  pipx apps" ;;
            *Upgrade*)   _run_in_term "pipx upgrade-all"; _notify "pipx apps upgraded" ;;
            *Uninstall*)
                local apps; apps=$(pipx list --short 2>/dev/null | awk '{print $1}')
                [ -z "$apps" ] && { _notify "No pipx apps"; continue; }
                local sel; sel=$(echo "$apps" | _rofi "  pipx uninstall")
                [ -n "$sel" ] && _confirm "Uninstall $sel?" && _run_in_term "pipx uninstall $sel" ;;
        esac
    done
}

_lang_npm() {
    while true; do
        local count; count=$(npm list -g --depth=0 2>/dev/null | tail -n +2 | wc -l)
        local choice; choice=$(_rofi_list "  npm ($count global pkgs)" \
            "  Search npm" "  Global packages" "  Outdated (global)" \
            "  Install global" "  Uninstall global" "  Package info" \
            "  Show dependencies" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_rofi_input "  Search npm"); [ -z "$q" ] && continue
                _notify "Searching npm..."
                npm search "$q" 2>/dev/null | head -30 | _rofi "  npm: $q" ;;
            *"Global packages"*)
                npm list -g --depth=0 2>/dev/null | _rofi "  npm global" ;;
            *Outdated*)
                _notify "Checking..."
                local out; out=$(npm outdated -g 2>/dev/null)
                echo "${out:-All up to date}" | _rofi "  npm outdated" ;;
            *"Install global"*)
                local pkg; pkg=$(_rofi_input "  npm install -g")
                [ -n "$pkg" ] && _run_in_term "npm install -g $pkg" ;;
            *Uninstall*)
                local pkgs; pkgs=$(npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -I{} basename {})
                [ -z "$pkgs" ] && { _notify "No global packages"; continue; }
                local sel; sel=$(echo "$pkgs" | _rofi "  npm uninstall -g")
                [ -n "$sel" ] && _confirm "Uninstall $sel?" && _run_in_term "npm uninstall -g $sel" ;;
            *"Package info"*)
                local pkg; pkg=$(_rofi_input "  npm info")
                [ -n "$pkg" ] && npm info "$pkg" 2>/dev/null | head -40 | _rofi "  npm: $pkg" ;;
            *dependencies*)
                local pkg; pkg=$(_rofi_input "  Show deps for")
                [ -n "$pkg" ] && npm info "$pkg" dependencies 2>/dev/null | _rofi "  npm deps: $pkg" ;;
        esac
    done
}

_lang_cargo() {
    while true; do
        local count=0
        [ -d "$HOME/.cargo/bin" ] && count=$(ls "$HOME/.cargo/bin" 2>/dev/null | wc -l)
        local choice; choice=$(_rofi_list "  Rust cargo ($count bins)" \
            "  Search crates.io" "  Installed binaries" "  Install crate" \
            "  Uninstall crate" "  Crate info" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_rofi_input "  Search crates.io"); [ -z "$q" ] && continue
                _notify "Searching crates.io..."
                cargo search "$q" 2>/dev/null | head -30 | _rofi "  crates: $q" ;;
            *Installed*)  cargo install --list 2>/dev/null | _rofi "  cargo installed" ;;
            *"Install crate"*)
                local pkg; pkg=$(_rofi_input "  cargo install")
                [ -n "$pkg" ] && _run_in_term "cargo install $pkg" ;;
            *Uninstall*)
                local bins; bins=$(cargo install --list 2>/dev/null | grep -v '^ ' | sed 's/ .*//')
                [ -z "$bins" ] && { _notify "No installed crates"; continue; }
                local sel; sel=$(echo "$bins" | _rofi "  cargo uninstall")
                [ -n "$sel" ] && _confirm "Uninstall $sel?" && _run_in_term "cargo uninstall $sel" ;;
            *info*)
                local pkg; pkg=$(_rofi_input "  Crate name")
                [ -n "$pkg" ] && cargo search "$pkg" 2>/dev/null | head -5 | _rofi "  $pkg" ;;
        esac
    done
}

_lang_gem() {
    while true; do
        local count; count=$(gem list --no-versions 2>/dev/null | wc -l)
        local choice; choice=$(_rofi_list "  Ruby gem ($count gems)" \
            "  Search RubyGems" "  Installed gems" "  Outdated gems" \
            "  Install gem" "  Uninstall gem" "  Gem info" \
            "  Gem dependencies" "  Clean old versions" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_rofi_input "  Search RubyGems"); [ -z "$q" ] && continue
                _notify "Searching..."
                gem search "$q" 2>/dev/null | head -40 | _rofi "  gems: $q" ;;
            *Installed*) gem list 2>/dev/null | _rofi "  gem list" ;;
            *Outdated*)  _notify "Checking..."; gem outdated 2>/dev/null | _rofi "  gem outdated" ;;
            *"Install gem"*)
                local pkg; pkg=$(_rofi_input "  gem install")
                [ -n "$pkg" ] && _run_in_term "gem install $pkg" ;;
            *Uninstall*)
                local gems; gems=$(gem list --no-versions 2>/dev/null)
                local sel; sel=$(echo "$gems" | _rofi "  gem uninstall")
                [ -n "$sel" ] && _confirm "Uninstall $sel?" && _run_in_term "gem uninstall $sel" ;;
            *"Gem info"*)
                local pkg; pkg=$(_rofi_input "  gem info")
                [ -n "$pkg" ] && gem info "$pkg" 2>/dev/null | _rofi "  gem: $pkg" ;;
            *dependencies*)
                local pkg; pkg=$(_rofi_input "  gem dependency")
                [ -n "$pkg" ] && gem dependency "$pkg" 2>/dev/null | _rofi "  gem deps: $pkg" ;;
            *Clean*) _confirm "Clean old gem versions?" && _run_in_term "gem cleanup" ;;
        esac
    done
}

_lang_go() {
    while true; do
        local count=0
        [ -d "$(go env GOPATH 2>/dev/null)/bin" ] && count=$(ls "$(go env GOPATH)/bin" 2>/dev/null | wc -l)
        local choice; choice=$(_rofi_list "  Go ($count bins)" \
            "  Installed binaries" "  Install module" "  Module info" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Installed*)
                local gobin; gobin=$(go env GOPATH 2>/dev/null)/bin
                [ -d "$gobin" ] && ls "$gobin" 2>/dev/null | _rofi "  go binaries" \
                                || _notify "No Go binaries" ;;
            *"Install module"*)
                local pkg; pkg=$(_rofi_input "  go install (full path@version)")
                [ -n "$pkg" ] && _run_in_term "go install $pkg" ;;
            *info*)
                local pkg; pkg=$(_rofi_input "  Module path")
                [ -n "$pkg" ] && _run_in_term "go doc $pkg 2>&1 | head -50; echo; echo 'Press Enter...'; read" ;;
        esac
    done
}

_lang_dotnet() {
    while true; do
        local choice; choice=$(_rofi_list "  .NET / NuGet" \
            "  Search NuGet" "  Global tools" "  Install global tool" \
            "  Uninstall global tool" "  Installed SDKs" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_rofi_input "  Search NuGet"); [ -z "$q" ] && continue
                _notify "Searching..."
                dotnet tool search "$q" 2>/dev/null | head -30 | _rofi "  nuget: $q" ;;
            *"Global tools"*) dotnet tool list -g 2>/dev/null | _rofi "  dotnet global tools" ;;
            *"Install global"*)
                local pkg; pkg=$(_rofi_input "  dotnet tool install -g")
                [ -n "$pkg" ] && _run_in_term "dotnet tool install -g $pkg" ;;
            *Uninstall*)
                local tools; tools=$(dotnet tool list -g 2>/dev/null | tail -n +3 | awk '{print $1}')
                local sel; sel=$(echo "$tools" | _rofi "  dotnet uninstall")
                [ -n "$sel" ] && _confirm "Uninstall $sel?" && _run_in_term "dotnet tool uninstall -g $sel" ;;
            *SDKs*) dotnet --list-sdks 2>/dev/null | _rofi "  .NET SDKs" ;;
        esac
    done
}

menu_lang_packages() {
    while true; do
        local available; available=$(_lang_detect_available)
        [ -z "$available" ] && { _notify "No language runtimes detected"; return; }

        local choice; choice=$(printf '%s\n─────────────────────\n  Back\n' "$available" \
            | "${ROFI[@]}" -p "  Language packages")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Python (pip)"*) _lang_pip ;;
            *pipx*)           _lang_pipx ;;
            *npm*)            _lang_npm ;;
            *yarn*)           _lang_yarn ;;
            *pnpm*)           _lang_pnpm ;;
            *cargo*)          _lang_cargo ;;
            *gem*)            _lang_gem ;;
            *Go*)             _lang_go ;;
            *composer*)       _lang_composer ;;
            *.NET*)           _lang_dotnet ;;
            *luarocks*)       _lang_luarocks ;;
            *cpan*|*Perl*)    _lang_cpan ;;
            *Haskell*)        _lang_haskell ;;
            *Julia*)          _lang_julia ;;
            *"R (CRAN)"*)     _lang_r ;;
        esac
    done
}

menu_developer() {
    while true; do
        local rt=0
        for t in pip pipx npm yarn pnpm cargo gem go composer dotnet luarocks cpan ghcup julia R; do
            command -v "$t" &>/dev/null && ((rt++))
        done
        local choice; choice=$(_rofi_list "  Developer tools" \
            "  Language packages ($rt runtimes)" \
            "  Base development packages" \
            "─────────────────────" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Language*)    menu_lang_packages ;;
            *"Base dev"*)  _menu_base_dev ;;
        esac
    done
}

_menu_base_dev() {
    local dev_items=()
    for g in base-devel; do
        local count installed=0
        count=$(pacman -Sg "$g" 2>/dev/null | wc -l)
        while IFS= read -r line; do
            local p="${line#* }"
            _is_installed "$p" && ((installed++))
        done <<< "$(pacman -Sg "$g" 2>/dev/null)"
        dev_items+=("  $g  ($installed/$count installed)")
    done
    dev_items+=("─────────────────────")
    for tool in git cmake meson ninja gdb valgrind strace docker podman; do
        local status="  [not installed]"
        _is_installed "$tool" && status="  [installed]"
        dev_items+=("  $tool${status}")
    done

    local sel; sel=$(_rofi_list "  Dev packages" "${dev_items[@]}" "  Back")
    [ -z "$sel" ] || [[ "$sel" == *Back* ]] && return
    local name; name=$(echo "$sel" | awk '{print $1}')

    if pacman -Sg "$name" &>/dev/null; then
        local pkgs; pkgs=$(pacman -Sg "$name" 2>/dev/null | awk '{print $2}')
        local lines=()
        while IFS= read -r p; do
            local st=""; _is_installed "$p" && st="  [installed]"
            lines+=("${p}${st}")
        done <<< "$pkgs"
        local pick; pick=$(printf '%s\n' "${lines[@]}" | _rofi "  $name")
        [ -n "$pick" ] && _pkg_detail "$(echo "$pick" | awk '{print $1}')"
    else
        _pkg_detail "$name"
    fi
}
