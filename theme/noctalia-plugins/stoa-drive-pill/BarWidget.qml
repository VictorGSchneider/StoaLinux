// Stoa Drive Pill — Bar Widget
// Inherits NIconButton so it picks up the bar's global capsule
// styling (color, outline, size, font scale, density), with an
// m/t badge overlay when not all drives are mounted.
//
// Left-click  → toggle Panel (per-drive controls)
// Right-click → Mount All / Unmount All / Open ~/Drive / Settings

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
    id: root

    property var    pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int    sectionWidgetIndex: -1
    property int    sectionWidgetsCount: 0

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _bin:  _home + "/.local/bin"

    // ── User settings ──
    readonly property string cfgIcon:        pluginApi?.pluginSettings?.icon ?? "cloud-upload"
    readonly property string cfgFileManager: pluginApi?.pluginSettings?.fileManager ?? "thunar"
    readonly property int    cfgPollMs:      (pluginApi?.pluginSettings?.pollSeconds ?? 5) * 1000
    readonly property bool   cfgBadge:       pluginApi?.pluginSettings?.showBadge ?? true

    // ── Polled state ──
    property bool _available: true
    property int  total:   0
    property int  mounted: 0

    visible: _available

    readonly property color stateColor: {
        if (total === 0)       return Color.mOnSurfaceVariant
        if (mounted === total) return Color.mSecondary
        if (mounted > 0)       return Color.mTertiary
        return Color.mOnSurfaceVariant
    }

    // ── NIconButton appearance ──
    icon: mounted === 0 && total > 0 ? "cloud-off" : cfgIcon
    baseSize: Style.getCapsuleHeightForScreen(screen?.name)
    applyUiScale: false
    tooltipDirection: BarService.getTooltipDirection(screen?.name)
    customRadius: Style.radiusL
    colorBg: Style.capsuleColor
    colorFg: root.stateColor
    colorBgHover: Color.mHover
    colorFgHover: root.stateColor
    colorBorder: "transparent"
    colorBorderHover: "transparent"

    tooltipText: !_available  ? "rclone not installed"
        : total === 0         ? "No cloud drives configured"
        : mounted === total   ? "All drives mounted (" + total + "/" + total + ")"
        : mounted > 0         ? mounted + " / " + total + " drives mounted"
                              : "No drives mounted — click to manage"

    onClicked: {
        if (!pluginApi) return
        const open = pluginApi.isPanelOpen?.(screen) === true
        if (open && pluginApi.closePanel) pluginApi.closePanel(screen)
        else if (pluginApi.openPanel)     pluginApi.openPanel(screen, root)
    }
    onRightClicked: PanelService.showContextMenu(contextMenu, root, screen)

    function _runBg(label, cmd) {
        var script =
            'export PATH="$HOME/.local/bin:$PATH"; ' +
            'notify-send "Stoa Drive" "Running: ' + label + '"; ' +
            'if ' + cmd + '; then ' +
            '  notify-send "Stoa Drive" "Done: ' + label + '"; ' +
            'else ' +
            '  notify-send -u critical "Stoa Drive" "Failed: ' + label + '"; ' +
            'fi; ' +
            'sleep 1'
        Quickshell.execDetached(["sh", "-c", script])
        refreshTimer.restart()
    }
    function _runOpen(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
    }

    // ── m/t badge overlay ──
    Rectangle {
        visible: root.cfgBadge && root.total > 0 && root.mounted < root.total
        anchors {
            top: parent.top
            right: parent.right
            topMargin: -2
            rightMargin: -2
        }
        implicitWidth:  badgeText.implicitWidth + 8
        implicitHeight: 14
        radius: 7
        color: root.mounted > 0 ? Color.mTertiaryContainer : Color.mErrorContainer
        z: 2

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.mounted + "/" + root.total
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Bold
            color: Color.mOnSurface
        }
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Mount All",    "action": "mountall",  "icon": "cloud-upload" },
            { "label": "Unmount All",  "action": "umountall", "icon": "cloud-off"    },
            { "label": "Open ~/Drive", "action": "open",      "icon": "folder"       },
            { "label": "Settings",     "action": "settings",  "icon": "settings"     },
        ]
        onTriggered: function(action, item) {
            contextMenu.close()
            PanelService.closeContextMenu(screen)
            if      (action === "mountall")  root._runBg("Mount all",   root._bin + "/stoa-drive mount-all")
            else if (action === "umountall") root._runBg("Unmount all", root._bin + "/stoa-drive unmount-all")
            else if (action === "open")      root._runOpen(root.cfgFileManager + " " + root._home + "/Drive")
            else if (action === "settings" && pluginApi?.manifest)
                BarService.openPluginSettings(screen, pluginApi.manifest)
        }
    }

    // ── Data polling ──
    Timer { id: refreshTimer; interval: 2000; repeat: false; onTriggered: statusProc.running = true }

    Process {
        id: statusProc
        command: [root._bin + "/stoa-drive-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root._available = d.available !== false
                    root.total      = d.total    || 0
                    root.mounted    = d.mounted  || 0
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: root.cfgPollMs; running: true; repeat: true
        onTriggered: { statusProc.running = false; statusProc.running = true }
    }
}
