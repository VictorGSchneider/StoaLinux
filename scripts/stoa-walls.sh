#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Wallpaper Generator                           ║
# ║  Generates minimalist wallpapers with the Stoic palette      ║
# ║  Requires: imagemagick                                       ║
# ╚══════════════════════════════════════════════════════════════╝

WALLDIR="${HOME}/.config/stoa/wallpapers"
mkdir -p "$WALLDIR"

WIDTH=1920
HEIGHT=1080

echo "Generating Stoic wallpapers..."

# 1. Marble — subtle gradient
magick -size ${WIDTH}x${HEIGHT} \
    gradient:"#2d2921-#1a1714" \
    -blur 0x2 \
    "$WALLDIR/marble.png"
echo "  [+] marble.png"

# 2. Parchment — warm tone
magick -size ${WIDTH}x${HEIGHT} \
    gradient:"#211e19-#1a1714" \
    -fill "#c49a5c" -draw "rectangle 0,$((HEIGHT/2-1)),${WIDTH},$((HEIGHT/2+1))" \
    -blur 0x40 \
    "$WALLDIR/parchment.png"
echo "  [+] parchment.png"

# 3. Columns — minimalist vertical lines
magick -size ${WIDTH}x${HEIGHT} \
    xc:"#1a1714" \
    -fill "#2d2921" \
    -draw "rectangle $((WIDTH/2-60)),0,$((WIDTH/2-58)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2-30)),0,$((WIDTH/2-28)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2)),0,$((WIDTH/2+2)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2+30)),0,$((WIDTH/2+32)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2+60)),0,$((WIDTH/2+62)),${HEIGHT}" \
    "$WALLDIR/columns.png"
echo "  [+] columns.png"

# 4. Minimalist with text
magick -size ${WIDTH}x${HEIGHT} \
    xc:"#1a1714" \
    -gravity center \
    -font "JetBrains-Mono" -pointsize 18 \
    -fill "#4a4540" \
    -annotate +0+0 "MEMENTO MORI" \
    "$WALLDIR/memento.png"
echo "  [+] memento.png"

echo ""
echo "Wallpapers saved to: $WALLDIR"
echo ""
echo "Apply:"
echo "  Hyprland (Wayland): swaybg -i $WALLDIR/marble.png -m fill"
echo "  i3 (Xorg):          feh --bg-fill $WALLDIR/marble.png"
