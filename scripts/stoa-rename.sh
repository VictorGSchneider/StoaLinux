#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — PowerRename                                   ║
# ║  Renomeia arquivos em lote com regex e preview               ║
# ║  Requer: rofi                                                ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-rename *.jpg               — renomeia com menu interativo
#   stoa-rename -f "old" -r "new" *.jpg  — direto sem menu
#   stoa-rename -f "\.jpeg$" -r ".jpg" -R ~/Fotos  — recursivo

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

_usage() {
    cat <<EOF
Uso: stoa-rename [opções] [arquivos...]

Opções:
  -f PATTERN    Padrão regex para buscar
  -r REPLACE    String de substituição
  -R DIR        Modo recursivo (todos arquivos no diretório)
  -i            Case insensitive
  -g            Substituir todas ocorrências (global)
  -n            Dry run (apenas mostra, não renomeia)
  -h            Mostrar esta ajuda

Exemplos:
  stoa-rename *.jpg                        Menu interativo
  stoa-rename -f "IMG_" -r "foto_" *.jpg   Direto
  stoa-rename -f "\d+" -r "001" -i *.png   Case insensitive
  stoa-rename -f "\.jpeg$" -r ".jpg" -R .  Recursivo
EOF
}

FIND_PATTERN=""
REPLACE_STR=""
RECURSIVE_DIR=""
CASE_FLAG=""
GLOBAL_FLAG=""
DRY_RUN=false

while getopts "f:r:R:ignh" opt; do
    case $opt in
        f) FIND_PATTERN="$OPTARG" ;;
        r) REPLACE_STR="$OPTARG" ;;
        R) RECURSIVE_DIR="$OPTARG" ;;
        i) CASE_FLAG="I" ;;
        g) GLOBAL_FLAG="g" ;;
        n) DRY_RUN=true ;;
        h) _usage; exit 0 ;;
        *) _usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Coleta arquivos
files=()
if [ -n "$RECURSIVE_DIR" ]; then
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$RECURSIVE_DIR" -type f -print0 | sort -z)
elif [ $# -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] && files+=("$f")
    done
fi

if [ ${#files[@]} -eq 0 ]; then
    notify-send -t 3000 "PowerRename" "Nenhum arquivo selecionado"
    echo "Nenhum arquivo selecionado."
    exit 1
fi

# Menu interativo se não passou -f
if [ -z "$FIND_PATTERN" ]; then
    FIND_PATTERN=$(rofi "${ROFI_ARGS[@]}" -p "Buscar (regex)")
    [ -z "$FIND_PATTERN" ] && exit 0

    REPLACE_STR=$(rofi "${ROFI_ARGS[@]}" -p "Substituir por")
    # REPLACE_STR pode ser vazio (deletar match)

    opts=$(printf "Aplicar renomeação\nCase insensitive\nSubstituir todas (global)\nDry run (apenas preview)" | \
        rofi "${ROFI_ARGS[@]}" -p "Opções" -multi-select)

    [[ "$opts" == *"Case insensitive"* ]] && CASE_FLAG="I"
    [[ "$opts" == *"todas"* ]] && GLOBAL_FLAG="g"
    [[ "$opts" == *"Dry run"* ]] && DRY_RUN=true
fi

# Monta sed flags
SED_FLAGS="${CASE_FLAG}${GLOBAL_FLAG}"

# Preview das mudanças
preview=""
changes=0
declare -A rename_map

for f in "${files[@]}"; do
    dir=$(dirname "$f")
    old_name=$(basename "$f")
    new_name=$(echo "$old_name" | sed -E "s/${FIND_PATTERN}/${REPLACE_STR}/${SED_FLAGS}")

    if [ "$old_name" != "$new_name" ]; then
        preview+="${old_name}  →  ${new_name}"$'\n'
        rename_map["$f"]="${dir}/${new_name}"
        ((changes++))
    fi
done

if [ $changes -eq 0 ]; then
    notify-send -t 3000 "PowerRename" "Nenhum arquivo corresponde ao padrão"
    exit 0
fi

# Mostra preview
if $DRY_RUN; then
    echo "$preview"
    echo "---"
    echo "$changes arquivo(s) seriam renomeados (dry run)"
    notify-send -t 5000 "PowerRename" "Dry run: $changes arquivo(s)\n(veja o terminal)"
    exit 0
fi

# Confirmação via rofi
confirm=$(printf "Renomear %d arquivo(s)\nCancelar" "$changes" | \
    rofi "${ROFI_ARGS[@]}" -p "Preview" -mesg "$(echo "$preview" | head -20)")

if [[ "$confirm" != "Renomear"* ]]; then
    exit 0
fi

# Executa renomeação
renamed=0
for src in "${!rename_map[@]}"; do
    dst="${rename_map[$src]}"
    if [ -e "$dst" ]; then
        notify-send -t 3000 "PowerRename" "Conflito: $(basename "$dst") já existe, pulando"
        continue
    fi
    mv -- "$src" "$dst" && ((renamed++))
done

notify-send -t 3000 "PowerRename" "${renamed}/${changes} arquivo(s) renomeado(s)"
