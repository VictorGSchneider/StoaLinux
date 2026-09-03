#!/bin/bash
# Stoa Store — miscellaneous language package managers
# (yarn, pnpm, composer, luarocks, cpan, haskell, julia, R).

_lang_yarn() {
    while true; do
        local choice; choice=$(_yad_select "  yarn" \
            "  Global packages" "  Install global" "  Remove global" "  Package info" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Global*)  yarn global list 2>/dev/null | _yad_list "  yarn global" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  yarn global add")
                [ -n "$pkg" ] && _run_in_term "yarn global add $pkg" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  yarn global remove")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "yarn global remove $pkg" ;;
            *info*)
                local pkg; pkg=$(_yad_input "  yarn info")
                [ -n "$pkg" ] && yarn info "$pkg" 2>/dev/null | head -40 | _yad_list "  yarn: $pkg" ;;
        esac
    done
}

_lang_pnpm() {
    while true; do
        local choice; choice=$(_yad_select "  pnpm" \
            "  Global packages" "  Install global" "  Remove global" "  Outdated (global)" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Global*)   pnpm list -g 2>/dev/null | _yad_list "  pnpm global" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  pnpm add -g")
                [ -n "$pkg" ] && _run_in_term "pnpm add -g $pkg" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  pnpm remove -g")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "pnpm remove -g $pkg" ;;
            *Outdated*) pnpm outdated -g 2>/dev/null | _yad_list "  pnpm outdated" ;;
        esac
    done
}

_lang_composer() {
    while true; do
        local choice; choice=$(_yad_select "  PHP Composer" \
            "  Search Packagist" "  Global packages" "  Install global" "  Remove global" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_yad_input "  Search Packagist"); [ -z "$q" ] && continue
                _notify "Searching..."
                composer search "$q" 2>/dev/null | head -30 | _yad_list "  packagist: $q" ;;
            *Global*)  composer global show 2>/dev/null | _yad_list "  composer global" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  composer global require")
                [ -n "$pkg" ] && _run_in_term "composer global require $pkg" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  composer global remove")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "composer global remove $pkg" ;;
        esac
    done
}

_lang_luarocks() {
    while true; do
        local choice; choice=$(_yad_select "  Lua (luarocks)" \
            "  Search" "  Installed" "  Install" "  Remove" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)
                local q; q=$(_yad_input "  Search luarocks"); [ -z "$q" ] && continue
                luarocks search "$q" 2>/dev/null | head -30 | _yad_list "  luarocks: $q" ;;
            *Installed*) luarocks list 2>/dev/null | _yad_list "  luarocks installed" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  luarocks install")
                [ -n "$pkg" ] && _run_in_term "luarocks install $pkg" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  luarocks remove")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "luarocks remove $pkg" ;;
        esac
    done
}

_lang_cpan() {
    while true; do
        local choice; choice=$(_yad_select "  Perl (CPAN)" \
            "  Installed modules" "  Install module" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Installed*)
                perldoc -t perllocal 2>/dev/null | head -80 | _yad_list "  perl modules" \
                    || cpan -l 2>/dev/null | head -80 | _yad_list "  cpan modules" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  cpan install")
                [ -n "$pkg" ] && _run_in_term "cpan install $pkg" ;;
        esac
    done
}

_lang_haskell() {
    while true; do
        local choice; choice=$(_yad_select "  Haskell" \
            "  GHCup toolchain" "  Cabal installed" "  Cabal install" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *GHCup*)             ghcup list 2>/dev/null | _yad_list "  ghcup toolchain" ;;
            *"Cabal installed"*) cabal list --installed 2>/dev/null | head -60 | _yad_list "  cabal installed" ;;
            *"Cabal install"*)
                local pkg; pkg=$(_yad_input "  cabal install")
                [ -n "$pkg" ] && _run_in_term "cabal install $pkg" ;;
        esac
    done
}

_lang_julia() {
    while true; do
        local choice; choice=$(_yad_select "  Julia (Pkg)" \
            "  Installed packages" "  Install package" "  Remove package" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Installed*) julia -e 'using Pkg; Pkg.status()' 2>/dev/null | _yad_list "  julia packages" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  Julia Pkg.add")
                [ -n "$pkg" ] && _run_in_term "julia -e 'using Pkg; Pkg.add(\"$pkg\")'" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  Julia Pkg.rm")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "julia -e 'using Pkg; Pkg.rm(\"$pkg\")'" ;;
        esac
    done
}

_lang_r() {
    while true; do
        local choice; choice=$(_yad_select "  R (CRAN)" \
            "  Installed packages" "  Install package" "  Remove package" "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Installed*) R -e 'installed.packages()[,"Package"]' 2>/dev/null | _yad_list "  R packages" ;;
            *Install*)
                local pkg; pkg=$(_yad_input "  install.packages")
                [ -n "$pkg" ] && _run_in_term "R -e 'install.packages(\"$pkg\", repos=\"https://cloud.r-project.org\")'" ;;
            *Remove*)
                local pkg; pkg=$(_yad_input "  remove.packages")
                [ -n "$pkg" ] && _yad_confirm "Remove $pkg?" && _run_in_term "R -e 'remove.packages(\"$pkg\")'" ;;
        esac
    done
}
