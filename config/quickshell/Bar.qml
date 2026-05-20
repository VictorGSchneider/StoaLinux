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
import Quickshell.Services.SystemTray
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
    property int    batterySecs: 0    // remaining (Discharging) or to-full (Charging)
    property int    volumePct: 0
    property bool   volumeMuted: false
    property string keybindsText: ""
    property string keybindsTooltip: ""

    // ── Quick Settings polled state ──
    property bool   dndOn: false
    property bool   nightOn: false
    property bool   bluetoothOn: false
    property int    brightnessPct: -1     // -1 = no brightness device
    property bool   mediaPlaying: false
    property string mediaTitle: ""
    property string mediaArtist: ""

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
            dndProc.running = true;
            nightProc.running = true;
            btProc.running = true;
            briProc.running = true;
            mediaProc.running = true;
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

    // Network: try wifi first (iwgetid), then default route iface address.
    Process {
        id: netProc
        command: ["bash", "-c", `
            ssid=$(iwgetid -r 2>/dev/null || true)
            if [ -n "$ssid" ]; then
                sig=$(awk 'NR==3 {gsub(/\\./,\"\",$3); print int($3)}' /proc/net/wireless 2>/dev/null)
                [ -z "$sig" ] && sig=0
                echo "wifi $ssid $sig"
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
            secs=0
            if [ "$st" = "Discharging" ]; then
                secs=$(cat "$bat/time_to_empty_now" 2>/dev/null || echo 0)
            elif [ "$st" = "Charging" ]; then
                secs=$(cat "$bat/time_to_full_now" 2>/dev/null || echo 0)
            fi
            # Fallback: compute from energy + power if kernel didn't expose time fields.
            if [ -z "$secs" ] || [ "$secs" = "0" ]; then
                energy=$(cat "$bat/energy_now" 2>/dev/null || echo 0)
                power=$(cat "$bat/power_now" 2>/dev/null || echo 0)
                full=$(cat "$bat/energy_full" 2>/dev/null || echo 0)
                if [ "$power" -gt 0 ] 2>/dev/null; then
                    if [ "$st" = "Discharging" ]; then
                        secs=$(( energy * 3600 / power ))
                    elif [ "$st" = "Charging" ] && [ "$full" -gt 0 ]; then
                        secs=$(( (full - energy) * 3600 / power ))
                    fi
                fi
            fi
            echo "$cap $st $secs"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t === "none") { bar.batteryPct = -1; return; }
                const parts = t.split(" ");
                bar.batteryPct    = parseInt(parts[0]);
                bar.batteryStatus = parts[1] || "Unknown";
                bar.batterySecs   = parseInt(parts[2] || "0");
            }
        }
    }

    function _fmtTime(secs: int): string {
        if (secs <= 0) return "";
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        if (h > 0) return h + "h " + m + "m";
        return m + "m";
    }

    // ── Quick Settings pollers ──

    Process {
        id: dndProc
        command: ["bash", "-c", "dunstctl is-paused 2>/dev/null || echo false"]
        stdout: StdioCollector { onStreamFinished: bar.dndOn = text.trim() === "true" }
    }
    Process {
        id: nightProc
        command: ["bash", "-c", "pgrep -x gammastep >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: bar.nightOn = text.trim() === "on" }
    }
    Process {
        id: btProc
        command: ["bash", "-c",
            "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: bar.bluetoothOn = text.trim() === "on" }
    }
    Process {
        id: briProc
        // brightnessctl -m emits: device,class,current,percent,max
        command: ["bash", "-c",
            "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/,\"\",$4); print $4}' || echo ''"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                bar.brightnessPct = t.length > 0 ? parseInt(t) : -1;
            }
        }
    }
    Process {
        id: mediaProc
        command: ["bash", "-c", `
            st=$(playerctl status 2>/dev/null)
            if [ -z "$st" ]; then echo "none"; exit 0; fi
            ti=$(playerctl metadata title 2>/dev/null)
            ar=$(playerctl metadata artist 2>/dev/null)
            echo "$st"
            echo "$ti"
            echo "$ar"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                if (lines[0] === "none" || !lines[0]) {
                    bar.mediaPlaying = false;
                    bar.mediaTitle = "";
                    bar.mediaArtist = "";
                    return;
                }
                bar.mediaPlaying = lines[0].trim() === "Playing";
                bar.mediaTitle   = (lines[1] || "").trim();
                bar.mediaArtist  = (lines[2] || "").trim();
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
        command: ["stoa-keybinds-bar", "bar"]
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

    // One-shot click handlers — call binaries directly (no bash -lc, which
    // loads .bashrc each time and adds ~hundreds of ms of perceived delay).
    Process { id: clipboardShow;     command: ["stoa-clipboard", "show"] }
    Process { id: clipboardPin;      command: ["stoa-clipboard", "pin"] }
    Process { id: keybindsToggle;    command: ["stoa-keybinds-toggle"] }
    Process { id: volumeMuteToggle;  command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }
    Process { id: osdUp;             command: ["stoa-osd", "volume-up"] }
    Process { id: osdDown;           command: ["stoa-osd", "volume-down"] }

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
                        Behavior on color { ColorAnimation { duration: 120 } }
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
                                      : (active || wsMouse.containsMouse) ? Theme.fg
                                               : hasWindows ? Theme.fgDim : Theme.stone
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch("workspace " + wsId)
                        // Scroll anywhere on a workspace button → prev/next.
                        // Inverted Y so wheel-up moves to lower-id workspace
                        // (matches i3/sway/gnome convention).
                        onWheel: function(wheel) {
                            Hyprland.dispatch(wheel.angleDelta.y > 0
                                ? "workspace e-1"
                                : "workspace e+1");
                        }
                    }
                }
            }
        }

        // CENTER block: keybinds + active window title
        Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }

        Text {
            id: keybindsCentre
            visible: Config.showKeybinds && bar.keybindsText.length > 0
            text: bar.keybindsText
            color: Theme.stone
            font.family: Theme.fontFamily
            font.pixelSize: 11
            leftPadding: 12; rightPadding: 12
            height: Theme.barHeight
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter
            MouseArea { id: kbHover; anchors.fill: parent; hoverEnabled: true }
            BarPopup {
                target: keybindsCentre
                content: bar.keybindsTooltip
                monospace: true
                visible: kbHover.containsMouse && bar.keybindsTooltip.length > 0
            }
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
            height: Theme.barHeight
            verticalAlignment: Text.AlignVCenter
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
                id: kbInfoSlot
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
                BarPopup {
                    target: kbInfoSlot
                    content: bar.keybindsTooltip
                    monospace: true
                    visible: kbInfoMouse.containsMouse && bar.keybindsTooltip.length > 0
                }
            }

            // ── System tray ──
            // Standard SNI tray (xdg-app-indicators). Left = activate, middle =
            // secondary, right = native menu via display(), scroll = scroll().
            Row {
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: SystemTray.items.values
                    delegate: Item {
                        id: trayDel
                        required property var modelData
                        width: 22
                        height: bar.implicitHeight

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            sourceSize.width: 16
                            sourceSize.height: 16
                            source: trayDel.modelData.icon
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }
                        MouseArea {
                            id: trayMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.LeftButton) {
                                    if (trayDel.modelData.onlyMenu && trayDel.modelData.hasMenu) {
                                        const p = trayDel.mapToItem(null, 0, trayDel.height);
                                        trayDel.modelData.display(bar, p.x, p.y);
                                    } else {
                                        trayDel.modelData.activate();
                                    }
                                } else if (mouse.button === Qt.MiddleButton) {
                                    trayDel.modelData.secondaryActivate();
                                } else if (mouse.button === Qt.RightButton
                                           && trayDel.modelData.hasMenu) {
                                    const p = trayDel.mapToItem(null, 0, trayDel.height);
                                    trayDel.modelData.display(bar, p.x, p.y);
                                }
                            }
                            onWheel: function(wheel) {
                                trayDel.modelData.scroll(wheel.angleDelta.y, false);
                            }
                        }
                        BarPopup {
                            target: trayDel
                            content: trayDel.modelData.tooltipTitle.length > 0
                                     ? trayDel.modelData.tooltipTitle
                                     : trayDel.modelData.title
                            visible: trayMouse.containsMouse
                                     && (trayDel.modelData.tooltipTitle.length > 0
                                         || trayDel.modelData.title.length > 0)
                        }
                    }
                }
            }

            // Clipboard
            Item {
                id: clipSlot
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
                BarPopup {
                    target: clipSlot
                    content: "Clipboard (Super+V) │ Fixar (Super+Shift+V)"
                    visible: clipMouse.containsMouse
                }
            }

            BarText { text: "  " + bar.diskFree }
            BarText {
                text: bar.netText
                color: bar.netDisconnected ? Theme.stone : Theme.fgDim
            }
            Item {
                id: batSlot
                visible: bar.batteryPct >= 0
                width: visible ? batText.implicitWidth + 2 * Theme.modulePad : 0
                height: bar.implicitHeight
                Text {
                    id: batText
                    anchors.centerIn: parent
                    text: {
                        const icon = bar.batteryStatus === "Charging" ? "" : "";
                        return icon + " " + bar.batteryPct + "%";
                    }
                    color: bar.batteryPct < 15 ? Theme.terracotta
                           : bar.batteryPct < 30 ? Theme.gold
                                                  : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    id: batHover
                    anchors.fill: parent
                    hoverEnabled: true
                }
                BarPopup {
                    target: batSlot
                    content: {
                        const head = bar.batteryStatus + " — " + bar.batteryPct + "%";
                        const t = bar._fmtTime(bar.batterySecs);
                        if (!t) return head;
                        if (bar.batteryStatus === "Charging")    return head + "\nFull in " + t;
                        if (bar.batteryStatus === "Discharging") return head + "\n" + t + " remaining";
                        return head;
                    }
                    visible: batHover.containsMouse
                }
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

            // Quick Settings trigger
            Item {
                id: qsSlot
                width: qsIcon.implicitWidth + 16
                height: bar.implicitHeight
                Text {
                    id: qsIcon
                    anchors.centerIn: parent
                    text: ""
                    color: qsMouse.containsMouse || qsPanel.visible
                           ? Theme.bronze : Theme.fgDim
                    font.pixelSize: 13
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                MouseArea {
                    id: qsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: qsPanel.visible = !qsPanel.visible
                }
                QuickSettings {
                    id: qsPanel
                    target: qsSlot
                    bar: bar
                }
            }

            // Clock — left-click opens nothing, right-click toggles a calendar popup.
            Item {
                id: clockSlot
                width: clockText.implicitWidth + 2 * Theme.modulePad
                height: bar.implicitHeight
                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: " " + Qt.formatDateTime(clockNow.now, "ddd dd MMM  HH:mm")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            calendarPopup.visible = !calendarPopup.visible;
                        }
                    }
                }

                PopupWindow {
                    id: calendarPopup
                    anchor.item: clockSlot
                    anchor.edges: Edges.Bottom
                    anchor.gravity: Edges.Bottom | Edges.Left
                    color: "transparent"
                    visible: false
                    grabFocus: true
                    implicitWidth: calCard.implicitWidth
                    implicitHeight: calCard.implicitHeight

                    Rectangle {
                        id: calCard
                        anchors.fill: parent
                        color: Theme.bgLight
                        border.color: Theme.stone
                        border.width: 1
                        radius: 4
                        implicitWidth: calCol.implicitWidth + 24
                        implicitHeight: calCol.implicitHeight + 24

                        Column {
                            id: calCol
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDate(clockNow.now, "MMMM yyyy")
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                            }
                            DayOfWeekRow {
                                width: monthGrid.width
                                locale: monthGrid.locale
                                delegate: Text {
                                    text: model.shortName
                                    color: Theme.stone
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            MonthGrid {
                                id: monthGrid
                                month: clockNow.now.getMonth()
                                year: clockNow.now.getFullYear()
                                spacing: 4
                                delegate: Text {
                                    required property var model
                                    text: model.day
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    color: model.today ? Theme.bronze
                                           : model.month === monthGrid.month ? Theme.fg
                                                                              : Theme.stone
                                    opacity: model.month === monthGrid.month ? 1.0 : 0.45
                                }
                            }
                        }
                    }
                }
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
