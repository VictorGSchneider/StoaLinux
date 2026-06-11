// Stoa Drive Pill — Bar Widget
// Icon-only capsule colored by mount state, with an optional m/t badge.
// Left-click  → toggle Panel (per-drive controls)
// Right-click → context menu (Mount All / Unmount All / Open ~/Drive / Settings)
//
// Actions run via Quickshell.execDetached with absolute paths so they
// survive QML lifetime and don't depend on ~/.local/bin being in
// Quickshell's PATH.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var    pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int    sectionWidgetIndex: -1

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _bin:  _home + "/.local/bin"

    // ── User settings ──
    readonly property string cfgIcon:        pluginApi?.pluginSettings?.icon ?? "cloud-upload"
    readonly property string cfgFileManager: pluginApi?.pluginSettings?.fileManager ?? "thunar"
    readonly property int    cfgPollMs:      (pluginApi?.pluginSettings?.pollSeconds ?? 5) * 1000
    readonly property bool   cfgBadge:       pluginApi?.pluginSettings?.showBadge ?? true

    property string tooltipText: !_available      ? "rclone not installed"
        : total === 0    ? "No cloud drives configured"
        : mounted === total
                         ? "All drives mounted (" + total + "/" + total + ")"
        : mounted > 0    ? mounted + " / " + total + " drives mounted"
                         : "No drives mounted — click to manage"

    visible: _available
    implicitWidth:  visible ? capsule.implicitWidth + Style.marginM * 2 : 0
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    property bool _available: true
    property int  total:    0
    property int  mounted:  0

    readonly property color pillColor: {
        if (total === 0)        return Color.mOnSurfaceVariant
        if (mounted === total)  return Color.mSecondary
        if (mounted > 0)        return Color.mTertiary
        return Color.mOnSurfaceVariant
    }

    function runSilent(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
        refreshTimer.restart()
    }

    // ── Capsule background ──
    Rectangle {
        anchors.centerIn: parent
        width:  capsule.implicitWidth + Style.marginS * 2
        height: 22
        radius: 11
        color:  Color.mSurfaceVariant
        opacity: 0.55
        Behavior on color { ColorAnimation { duration: 400 } }
    }

    // ── Icon + badge ──
    RowLayout {
        id: capsule
        anchors.centerIn: parent
        spacing: Style.marginXS

        NIcon {
            icon: root.mounted === 0 && root.total > 0 ? "cloud-off" : root.cfgIcon
            color: root.pillColor
            pointSize: Style.fontSizeM
            Behavior on color { ColorAnimation { duration: 400 } }
        }

        // m/t badge — only when not everything is mounted
        Rectangle {
            visible: root.cfgBadge && root.total > 0 && root.mounted < root.total
            implicitWidth: badgeText.implicitWidth + 8
            implicitHeight: 14
            radius: 7
            color: root.mounted > 0 ? Color.mTertiaryContainer : Color.mSurfaceVariant

            NText {
                id: badgeText
                anchors.centerIn: parent
                text: root.mounted + "/" + root.total
                font.pointSize: Style.fontSizeXS
                font.weight: Font.Bold
                color: Color.mOnSurface
            }
        }
    }

    // ── Click handler ──
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                if (pluginApi) pluginApi.togglePanel(root.screen, root)
            } else if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen)
            }
        }
    }

    // ── Right-click context menu ──
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
            if      (action === "mountall")  root.runSilent(root._bin + "/stoa-drive mount-all")
            else if (action === "umountall") root.runSilent(root._bin + "/stoa-drive unmount-all")
            else if (action === "open")      root.runSilent(root.cfgFileManager + " " + root._home + "/Drive")
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
        // Default 5 s: the first read after boot races with
        // `stoa-drive mount-all`, so retry quickly enough that the pill
        // never appears stuck. Force a false→true transition so the
        // Process re-spawns cleanly even if Quickshell internals didn't
        // clear `running` after the previous exit.
        interval: root.cfgPollMs; running: true; repeat: true
        onTriggered: {
            statusProc.running = false
            statusProc.running = true
        }
    }
}
