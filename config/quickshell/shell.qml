// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Quickshell entry                              ║
// ║  Loaded by `quickshell` (no args) from ~/.config/quickshell. ║
// ║  Spawns one Bar per screen.                                  ║
// ╚══════════════════════════════════════════════════════════════╝

import Quickshell
import "."

ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }
}
