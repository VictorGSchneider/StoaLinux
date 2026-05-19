// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Quickshell Config                             ║
// ║  Reads ~/.config/stoa/stoa.conf (KEY=value pairs) so the    ║
// ║  shell honors the same toggles as the rest of Stoa.         ║
// ╚══════════════════════════════════════════════════════════════╝

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ── Public, reactive flags ──
    property bool showKeybinds: true
    property string barEngine: "quickshell"

    // Reload from disk whenever the file changes.
    FileView {
        id: conf
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
              + "/stoa/stoa.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._parse(conf.text())
    }

    function _parse(raw: string): void {
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i].trim();
            if (!line || line.startsWith("#")) continue;
            const eq = line.indexOf("=");
            if (eq < 0) continue;
            const key = line.substring(0, eq).trim();
            let val = line.substring(eq + 1).trim();
            // Strip surrounding quotes if present.
            if ((val.startsWith('"') && val.endsWith('"'))
                || (val.startsWith("'") && val.endsWith("'"))) {
                val = val.substring(1, val.length - 1);
            }
            switch (key) {
            case "STOA_SHOW_KEYBINDS":
                root.showKeybinds = (val === "true");
                break;
            case "STOA_BAR":
                if (val) root.barEngine = val;
                break;
            }
        }
    }
}
