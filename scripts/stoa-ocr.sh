#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Extractor (OCR)                          ║
# ║  Extrai texto de áreas da tela usando OCR                   ║
# ║  Requer: grim, slurp, tesseract, wl-clipboard               ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-ocr            — seleciona área e copia texto extraído
#   stoa-ocr file.png   — extrai texto de um arquivo de imagem
#   stoa-ocr por        — seleciona área, OCR em português
#   stoa-ocr eng        — seleciona área, OCR em inglês

TMPDIR="${XDG_RUNTIME_DIR:-/tmp}"

# Detecta idioma: argumento ou default
_get_lang() {
    local arg="$1"
    case "$arg" in
        por|pt|pt-br|portugues) echo "por" ;;
        eng|en|english)         echo "eng" ;;
        *)                      echo "eng+por" ;;
    esac
}

_ocr_from_file() {
    local file="$1"
    local lang="$2"

    if [ ! -f "$file" ]; then
        notify-send -t 3000 "OCR" "Arquivo não encontrado: $file"
        exit 1
    fi

    local text
    text=$(tesseract "$file" stdout -l "$lang" 2>/dev/null | sed '/^$/d')

    if [ -z "$text" ]; then
        notify-send -t 3000 "OCR" "Nenhum texto detectado"
        exit 0
    fi

    printf '%s' "$text" | wl-copy
    notify-send -t 3000 "OCR" "Texto extraído e copiado (${#text} chars)"
}

_ocr_from_screen() {
    local lang="$1"
    local tmpfile="${TMPDIR}/stoa-ocr-$$.png"

    # Captura área da tela
    local geometry
    geometry=$(slurp 2>/dev/null)
    [ -z "$geometry" ] && exit 0

    grim -g "$geometry" "$tmpfile"

    if [ ! -f "$tmpfile" ]; then
        notify-send -t 3000 "OCR" "Falha ao capturar tela"
        exit 1
    fi

    _ocr_from_file "$tmpfile" "$lang"
    rm -f "$tmpfile"
}

# Verifica dependências
if ! command -v tesseract &>/dev/null; then
    notify-send -t 5000 "OCR" "tesseract não instalado.\nInstale: sudo pacman -S tesseract tesseract-data-eng tesseract-data-por"
    exit 1
fi

# Se primeiro argumento é um arquivo existente, OCR nele
if [ -n "$1" ] && [ -f "$1" ]; then
    lang=$(_get_lang "${2:-}")
    _ocr_from_file "$1" "$lang"
else
    lang=$(_get_lang "${1:-}")
    _ocr_from_screen "$lang"
fi
