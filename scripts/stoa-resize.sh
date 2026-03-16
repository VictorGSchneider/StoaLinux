#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Image Resizer                                 ║
# ║  Redimensiona múltiplas imagens de uma vez                   ║
# ║  Requer: imagemagick, rofi                                  ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-resize img1.png img2.jpg ...   — redimensiona com menu
#   stoa-resize *.png                   — glob funciona também

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

PRESETS=(
    "25%   — Miniatura"
    "50%   — Metade"
    "75%   — Três quartos"
    "1920x1080 — Full HD"
    "1280x720  — HD"
    "800x600   — Pequena"
    "640x480   — Web"
    "Personalizado..."
)

if [ $# -eq 0 ]; then
    echo "Uso: stoa-resize imagem1 [imagem2 ...]"
    notify-send -t 3000 "Image Resizer" "Uso: stoa-resize imagem1 [imagem2 ...]"
    exit 1
fi

# Filtra apenas arquivos de imagem válidos
images=()
for f in "$@"; do
    if [ -f "$f" ] && file --mime-type -b "$f" | grep -q "^image/"; then
        images+=("$f")
    fi
done

if [ ${#images[@]} -eq 0 ]; then
    notify-send -t 3000 "Image Resizer" "Nenhuma imagem válida encontrada"
    exit 1
fi

# Menu de tamanho
choice=$(printf '%s\n' "${PRESETS[@]}" | rofi "${ROFI_ARGS[@]}" -p "Redimensionar ${#images[@]} imagem(ns)")
[ -z "$choice" ] && exit 0

# Extrai dimensão
if [[ "$choice" == "Personalizado..."* ]]; then
    size=$(rofi "${ROFI_ARGS[@]}" -p "Tamanho (ex: 800x600 ou 50%)")
    [ -z "$size" ] && exit 0
else
    size=$(echo "$choice" | awk '{print $1}')
fi

# Menu de destino
dest=$(printf "Sobrescrever originais\nSalvar como cópia (_resized)\nSalvar em pasta resized/" | \
    rofi "${ROFI_ARGS[@]}" -p "Destino")
[ -z "$dest" ] && exit 0

count=0
for img in "${images[@]}"; do
    dir=$(dirname "$img")
    base=$(basename "$img")
    name="${base%.*}"
    ext="${base##*.}"

    case "$dest" in
        "Sobrescrever"*)
            magick "$img" -resize "$size" "$img"
            ;;
        "Salvar como cópia"*)
            magick "$img" -resize "$size" "${dir}/${name}_resized.${ext}"
            ;;
        "Salvar em pasta"*)
            mkdir -p "${dir}/resized"
            magick "$img" -resize "$size" "${dir}/resized/${base}"
            ;;
    esac
    ((count++))
done

notify-send -t 3000 "Image Resizer" "${count} imagem(ns) redimensionada(s) para ${size}"
