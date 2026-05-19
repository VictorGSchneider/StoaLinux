// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Quickshell Theme                              ║
// ║  "Beauty is the mark of well-ordered souls." — Plotinus     ║
// ╚══════════════════════════════════════════════════════════════╝
//
// Palette mirrors config/waybar/style.css and config/eww/eww.scss.
// Treated as the QML source-of-truth for the shell; if Stoa colors
// ever move into stoa.conf, switch the readonly props to read from
// Config and the rest of the shell keeps working unchanged.

pragma Singleton

import Quickshell

Singleton {
    readonly property color bg:         "#211e19"
    readonly property color bgLight:    "#2d2921"
    readonly property color fg:         "#d4cfc4"
    readonly property color fgDim:      "#a89f91"
    readonly property color bronze:     "#c49a5c"
    readonly property color gold:       "#d4a84b"
    readonly property color olive:      "#8a9a6c"
    readonly property color terracotta: "#b36b5a"
    readonly property color stone:      "#6e6a62"

    readonly property string fontFamily: "EB Garamond"
    readonly property string monoFamily: "JetBrains Mono"
    readonly property int    fontSize:   12

    readonly property int    barHeight:  30
    readonly property int    modulePad:  10
}
