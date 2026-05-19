// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Bar (Quickshell)                              ║
// ║  Replacement for config/waybar/config.                       ║
// ║  "Measure what is measurable." — Cleanthes                  ║
// ╚══════════════════════════════════════════════════════════════╝
//
// Modules (left to right):
//   Workspaces  •  Keybinds (center-left)  Active window (center)
//   Keybinds-info • Clipboard • Disk • Network • Battery
//   • CPU • Memory • Volume • Clock
//
// External scripts called (same as waybar):
//   stoa-keybinds-bar bar|info       JSON
//   stoa-keybinds-toggle             flip flag in stoa.conf
//   stoa-clipboard show|pin          rofi UI
//   stoa-osd volume-up|volume-down   OSD
//
// Anything not produced by Quickshell built-ins is read from /proc,
// /sys, or a one-shot shell command on a 5-second Timer (mirroring
// waybar's intervals).

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

PanelWindow {
    id: bar
    required property var modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bg

    // ── Polling state ──
    property real cpuPct: 0
    property real memUsedGiB: 0
    property real memTotalGiB: 0
    property string diskFree: "--"
    property string netText: " --"
    property bool   netDisconnected: true
    property int    batteryPct: -1
    property string batteryStatus: "Unknown"
    property int    volumePct: 0
    property bool   volumeMuted: false
    property string keybindsText: ""
    property string keybindsTooltip: ""

    // CPU diff state
    property var _cpuPrev: ({ total: 0, idle: 0 })

    Timer {
        id: tick
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true;
            memProc.running = true;
            diskProc.running = true;
            netProc.running = true;
            batProc.running = true;
            volProc.running = true;
        }
    }

    // Keybinds poll (matches waybar interval: 5s).
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: keybindsBarProc.running = true
    }

    // ── Processes (one per metric) ──

    Process {
        id: cpuProc
        command: ["bash", "-c",
                  "read cpu a b c idle rest < /proc/stat; echo $((a+b+c+idle)) $idle"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts.length !== 2) return;
                const total = parseInt(parts[0]);
                const idle = parseInt(parts[1]);
                const dt = total - bar._cpuPrev.total;
                const di = idle - bar._cpuPrev.idle;
                if (dt > 0 && bar._cpuPrev.total > 0) {
                    bar.cpuPct = Math.max(0, Math.round(100 * (dt - di) / dt));
                }
                bar._cpuPrev = { total: total, idle: idle };
            }
        }
    }

    Process {
        id: memProc
        command: ["bash", "-c",
                  "awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print t,t-a}' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts.length !== 2) return;
                bar.memTotalGiB = parseInt(parts[0]) / 1024 / 1024;
                bar.memUsedGiB  = parseInt(parts[1]) / 1024 / 1024;
            }
        }
    }

    Process {
        id: diskProc
        command: ["bash", "-c", "df -h --output=avail / | tail -1 | tr -d ' '"]
        stdout: StdioCollector {
            onStreamFinished: bar.diskFree = text.trim() || "--"
        }
    }

    // Network: try wifi first (nmcli), then default route iface address.
    Process {
        id: netProc
        command: ["bash", "-c", `
            ssid=$(iwgetid -r 2>/dev/null || true)
            if [ -n "$ssid" ]; then
                sig=$(awk 'NR==3 {gsub(/\\./,\"\",$3); print int($3)}' /proc/net/wireless 2>/dev/null)
                echo "wifi $ssid ${sig:-0}"
            else
                ip=$(ip -4 -o route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
                if [ -n "$ip" ]; then echo "eth $ip"; else echo "down"; fi
            fi
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.startsWith("wifi")) {
                    const m = t.match(/^wifi (.+) (\d+)$/);
                    if (m) {
                        bar.netText = "  " + m[1] + " " + m[2] + "%";
                        bar.netDisconnected = false;
                    }
                } else if (t.startsWith("eth")) {
                    bar.netText = " " + t.substring(4);
                    bar.netDisconnected = false;
                } else {
                    bar.netText = " --";
                    bar.netDisconnected = true;
                }
            }
        }
    }

    Process {
        id: batProc
        command: ["bash", "-c", `
            bat=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
            if [ -z "$bat" ]; then echo "none"; exit 0; fi
            cap=$(cat "$bat/capacity")
            st=$(cat "$bat/status")
            echo "$cap $st"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t === "none") { bar.batteryPct = -1; return; }
                const sp = t.indexOf(" ");
                bar.batteryPct    = parseInt(t.substring(0, sp));
                bar.batteryStatus = t.substring(sp + 1);
            }
        }
    }

    Process {
        id: volProc
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo '0.00'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                bar.volumeMuted = t.indexOf("MUTED") >= 0;
                const m = t.match(/([0-9]+\.[0-9]+)/);
                bar.volumePct = m ? Math.round(parseFloat(m[1]) * 100) : 0;
            }
        }
    }

    // Keybinds bar JSON (compact line).
    Process {
        id: keybindsBarProc
        command: ["bash", "-lc", "stoa-keybinds-bar bar"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) { bar.keybindsText = ""; bar.keybindsTooltip = ""; return; }
                try {
                    const j = JSON.parse(text);
                    bar.keybindsText    = j.text || "";
                    bar.keybindsTooltip = j.tooltip || "";
                } catch (e) {
                    bar.keybindsText = "";
                }
            }
        }
    }

    Process {
        id: clipboardShow
        command: ["bash", "-lc", "stoa-clipboard show"]
    }
    Process {
        id: clipboardPin
        command: ["bash", "-lc", "stoa-clipboard pin"]
    }
    Process {
        id: keybindsToggle
        command: ["bash", "-lc", "stoa-keybinds-toggle"]
    }
    Process {
        id: volumeMuteToggle
        command: ["bash", "-lc", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"]
    }
    Process {
        id: osdUp
        command: ["bash", "-lc", "stoa-osd volume-up"]
    }
    Process {
        id: osdDown
        command: ["bash", "-lc", "stoa-osd volume-down"]
    }

    // ── Layout ──

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // LEFT: workspaces
        Row {
            id: workspaces
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            Repeater {
                model: 10
                delegate: Item {
                    required property int index
                    readonly property int wsId: index + 1
                    readonly property var ws: {
                        const list = Hyprland.workspaces.values;
                        for (let i = 0; i < list.length; ++i) {
                            if (list[i].id === wsId) return list[i];
                        }
                        return null;
                    }
                    readonly property bool active: Hyprland.focusedWorkspace
                                                    && Hyprland.focusedWorkspace.id === wsId
                    readonly property bool urgent: ws && ws.urgent
                    readonly property bool hasWindows: ws && ws.toplevels && ws.toplevels.values.length > 0

                    width: wsLabel.implicitWidth + 16
                    height: bar.implicitHeight

                    Rectangle {
                        anchors.fill: parent
                        color: wsMouse.containsMouse ? Theme.bgLight : "transparent"
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 2
                        color: active ? Theme.bronze : "transparent"
                    }
                    Text {
                        id: wsLabel
                        anchors.centerIn: parent
                        text: ["I","II","III","IV","V","VI","VII","VIII","IX","X"][index]
                        color: urgent ? Theme.terracotta
                                      : active ? Theme.fg
                                               : hasWindows ? Theme.fgDim : Theme.stone
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + wsId)
                    }
                }
            }
        }

        // CENTER block: keybinds + active window title
        Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }

        Text {
            visible: Config.showKeybinds && bar.keybindsText.length > 0
            text: bar.keybindsText
            color: Theme.stone
            font.family: Theme.fontFamily
            font.pixelSize: 11
            leftPadding: 12; rightPadding: 12
            Layout.alignment: Qt.AlignVCenter
            ToolTip.visible: kbHover.containsMouse && bar.keybindsTooltip.length > 0
            ToolTip.text: bar.keybindsTooltip
            MouseArea { id: kbHover; anchors.fill: parent; hoverEnabled: true }
        }

        Text {
            id: activeWindow
            text: ToplevelManager.activeToplevel
                  ? _rewrite(ToplevelManager.activeToplevel.appId,
                             ToplevelManager.activeToplevel.title)
                  : ""
            color: Theme.bronze
            font.family: Theme.fontFamily
            font.pixelSize: 12
            leftPadding: 12; rightPadding: 12
            elide: Text.ElideRight
            Layout.maximumWidth: 600
            Layout.alignment: Qt.AlignVCenter
            function _rewrite(cls, title) {
                if (!cls) return title || "";
                if (cls === "brave-browser") return "Super+B │ " + title;
                if (cls === "obsidian")      return "Super+O │ " + title;
                if (cls === "kitty" && /btop/.test(title)) return "Super+N │ btop";
                if (cls === "kitty" && /lf/.test(title))   return "Super+E │ lf";
                if (cls === "kitty")         return "Super+⏎ │ " + title;
                return title || "";
            }
        }

        Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }

        // RIGHT: keybinds-info, clipboard, disk, net, battery, cpu, mem, vol, clock
        Row {
            spacing: 0
            Layout.alignment: Qt.AlignVCenter

            // Keybinds info (keyboard icon)
            Item {
                width: kbInfo.implicitWidth + 20
                height: bar.implicitHeight
                Text {
                    id: kbInfo
                    anchors.centerIn: parent
                    text: "⌨"
                    color: kbInfoMouse.containsMouse ? Theme.bronze
                           : Config.showKeybinds ? Theme.fgDim : Theme.stone
                    font.pixelSize: 14
                }
                MouseArea {
                    id: kbInfoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: keybindsToggle.running = true
                }
                ToolTip.visible: kbInfoMouse.containsMouse && bar.keybindsTooltip.length > 0
                ToolTip.text: bar.keybindsTooltip
            }

            // Clipboard
            Item {
                width: clipText.implicitWidth + 16
                height: bar.implicitHeight
                Text {
                    id: clipText
                    anchors.centerIn: parent
                    text: ""
                    color: clipMouse.containsMouse ? Theme.bronze : Theme.fgDim
                }
                MouseArea {
                    id: clipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) clipboardPin.running = true;
                        else clipboardShow.running = true;
                    }
                }
                ToolTip.visible: clipMouse.containsMouse
                ToolTip.text: "Clipboard (Super+V) │ Fixar (Super+Shift+V)"
            }

            BarText { text: "  " + bar.diskFree }
            BarText {
                text: bar.netText
                color: bar.netDisconnected ? Theme.stone : Theme.fgDim
            }
            BarText {
                visible: bar.batteryPct >= 0
                text: {
                    const icon = bar.batteryStatus === "Charging" ? "" : "";
                    return icon + " " + bar.batteryPct + "%";
                }
                color: bar.batteryPct < 15 ? Theme.terracotta
                       : bar.batteryPct < 30 ? Theme.gold
                                              : Theme.fgDim
            }
            BarText { text: "  " + bar.cpuPct + "%" }
            BarText {
                text: "  " + bar.memUsedGiB.toFixed(1) + "G / " + bar.memTotalGiB.toFixed(1) + "G"
            }

            // Volume — clickable + scroll
            Item {
                width: volText.implicitWidth + 2 * Theme.modulePad
                height: bar.implicitHeight
                Text {
                    id: volText
                    anchors.centerIn: parent
                    text: bar.volumeMuted ? "  muted" : "  " + bar.volumePct + "%"
                    color: Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: volumeMuteToggle.running = true
                    onWheel: function(wheel) {
                        if (wheel.angleDelta.y > 0) osdUp.running = true;
                        else                       osdDown.running = true;
                    }
                }
            }

            // Clock
            BarText {
                text: " " + Qt.formatDateTime(clockNow.now, "ddd dd MMM  HH:mm")
                color: Theme.fg
            }
        }
    }

    QtObject {
        id: clockNow
        property var now: new Date()
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockNow.now = new Date()
    }

}
