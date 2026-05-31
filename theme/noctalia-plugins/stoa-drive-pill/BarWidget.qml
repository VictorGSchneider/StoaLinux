// Stoa Drive Pill — Bar Widget
// Left-click  → toggle Panel (per-drive controls)
// Right-click → context menu (Mount All / Unmount All / Open ~/Drive)

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var    pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int    sectionWidgetIndex: -1

    property string tooltipText: !_available      ? "rclone not installed"
        : total === 0    ? "No cloud drives configured"
        : mounted === total
                         ? "All drives mounted (" + total + "/" + total + ")"
        : mounted > 0    ? mounted + " / " + total + " drives mounted"
                         : "No drives mounted — click to manage"

    visible: _available
    implicitWidth:  visible ? pill.implicitWidth + Style.marginM * 2 : 0
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

    // ── Pill ──
    RowLayout {
        id: pill
        anchors.centerIn: parent
        spacing: Style.marginXS

        Rectangle {
            width: 10; height: 10; radius: 5
            color: root.pillColor
            Behavior on color { ColorAnimation { duration: 400 } }
        }

        NText {
            text: root.total > 0 ? "drive " + root.mounted + "/" + root.total : "drive"
            color: root.pillColor
            font.pointSize: Style.fontSizeS
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 400 } }
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
                contextMenu.openAtItem(root, screen)
            }
        }
    }

    // ── Right-click context menu ──
    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Mount All",   "action": "mountall",  "icon": "cloud-upload" },
            { "label": "Unmount All", "action": "umountall", "icon": "cloud-off"    },
            { "label": "Open ~/Drive","action": "open",      "icon": "folder"       },
        ]
        onTriggered: function(action, item) {
            if      (action === "mountall")  mountAllProc.running = true
            else if (action === "umountall") umountAllProc.running = true
            else if (action === "open")      openDirProc.running  = true
        }
    }

    // ── Processes ──
    Timer { id: refreshTimer; interval: 2000; repeat: false; onTriggered: statusProc.running = true }

    Process { id: mountAllProc;  command: ["stoa-drive", "mount-all"];   onRunningChanged: if (!running) refreshTimer.restart() }
    Process { id: umountAllProc; command: ["stoa-drive", "unmount-all"]; onRunningChanged: if (!running) refreshTimer.restart() }
    Process { id: openDirProc;   command: ["thunar", (Quickshell.env("HOME") || "") + "/Drive"] }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-drive-status"]
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
        interval: 60000; running: true; repeat: true
        onTriggered: statusProc.running = true
    }
}
