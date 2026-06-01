// Stoa Doctor Pill — Bar Widget
// Left-click  → toggle Panel (status + actions)
// Right-click → context menu (Run Doctor / Open Log)

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

    property string tooltipText: issues < 0 ? "Doctor log not found — run stoa-doctor"
        : issues > 0
            ? issues + " issue" + (issues > 1 ? "s" : "") +
              (warnings > 0 ? "  ·  " + warnings + " warning" + (warnings > 1 ? "s" : "") : "")
        : warnings > 0 ? warnings + " warning" + (warnings > 1 ? "s" : "")
        : "All systems nominal"

    implicitWidth:  capsule.implicitWidth + Style.marginM * 2
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    property int issues:  -1
    property int warnings: 0

    readonly property color pillColor: {
        if (issues < 0)   return Color.mOnSurfaceVariant
        if (issues > 0)   return Color.mError
        if (warnings > 0) return Color.mTertiary
        return Color.mSecondary
    }

    readonly property string pillLabel: {
        if (issues > 0)   return "doctor " + issues + "✕"
        if (warnings > 0) return "doctor " + warnings + "⚠"
        return "doctor"
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

    // ── Pill ──
    RowLayout {
        id: capsule
        anchors.centerIn: parent
        spacing: Style.marginXS

        Rectangle {
            width: 8; height: 8; radius: 4
            color: root.pillColor
            Behavior on color { ColorAnimation { duration: 400 } }
        }

        NText {
            text:  root.pillLabel
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
                PanelService.showContextMenu(contextMenu, root, screen)
            }
        }
    }

    // ── Right-click context menu ──
    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Run Doctor",  "action": "run",  "icon": "refresh" },
            { "label": "Open Log",    "action": "log",  "icon": "file-text" },
        ]
        onTriggered: function(action, item) {
            if      (action === "run") runDoctorProc.running = true
            else if (action === "log") openLogProc.running   = true
        }
    }

    // ── Processes ──
    Process {
        id: runDoctorProc
        command: ["stoa-doctor"]
        onRunningChanged: if (!running) statusProc.running = true
    }

    Process {
        id: openLogProc
        property string _log: (Quickshell.env("HOME") || "") + "/.config/stoa/doctor.log"
        command: ["kitty", "--title", "stoa-doctor", "--hold", "cat", _log]
    }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-doctor-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root.issues   = d.issues   !== undefined ? d.issues   : -1
                    root.warnings = d.warnings !== undefined ? d.warnings :  0
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: statusProc.running = true
    }
}
