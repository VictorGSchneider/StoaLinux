#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Extractor (OCR)                          ║
# ║  Extract text from screen areas using OCR                   ║
# ║  Requires: grim, slurp, tesseract, wl-clipboard              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-ocr            — select area and copy extracted text
#   stoa-ocr file.png   — extract text from an image file
#   stoa-ocr por        — select area, OCR in Portuguese
#   stoa-ocr eng        — select area, OCR in English

OCR_TMPDIR="${XDG_RUNTIME_DIR:-/tmp}"

# Detect session type
_is_wayland() { [ -n "${WAYLAND_DISPLAY:-}" ]; }

_copy() {
    if _is_wayland; then
        wl-copy
    else
        xclip -selection clipboard
    fi
}

_screenshot_area() {
    local outfile="$1"
    if _is_wayland; then
        local geometry
        geometry=$(slurp 2>/dev/null)
        [ -z "$geometry" ] && exit 0
        grim -g "$geometry" "$outfile"
    else
        maim -s "$outfile"
    fi
}

# Detect language: argument or default
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
        notify-send -t 3000 "OCR" "File not found: $file"
        return 1
    fi

    local text
    text=$(tesseract "$file" stdout -l "$lang" 2>/dev/null | sed '/^$/d')

    if [ -z "$text" ]; then
        notify-send -t 3000 "OCR" "No text detected"
        return 1
    fi

    printf '%s' "$text" | _copy
    notify-send -t 3000 "OCR" "Text extracted and copied (${#text} chars)"
}

_ocr_from_screen() {
    local lang="$1"
    local tmpfile="${OCR_TMPDIR}/stoa-ocr-$$.png"

    # Capture screen area
    _screenshot_area "$tmpfile"

    if [ ! -f "$tmpfile" ]; then
        notify-send -t 3000 "OCR" "Failed to capture screen"
        exit 1
    fi

    _ocr_from_file "$tmpfile" "$lang"
    rm -f "$tmpfile"
}

# Check dependencies
if ! command -v tesseract &>/dev/null; then
    notify-send -t 5000 "OCR" "tesseract not installed.\nInstall: sudo pacman -S tesseract tesseract-data-eng tesseract-data-por"
    exit 1
fi

# If first argument is an existing file, OCR it
if [ -n "$1" ] && [ -f "$1" ]; then
    lang=$(_get_lang "${2:-}")
    _ocr_from_file "$1" "$lang"
else
    lang=$(_get_lang "${1:-}")
    _ocr_from_screen "$lang"
fi
