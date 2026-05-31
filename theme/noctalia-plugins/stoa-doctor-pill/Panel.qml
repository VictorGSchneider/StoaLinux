// Stoa Doctor Pill — Panel
// Opened by left-click on the bar widget via pluginApi.togglePanel()

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var       pluginApi: null
    property ShellScreen screen

    readonly property real contentPreferredWidth:  260
    readonly property real contentPreferredHeight: contentCol.implicitHeight + Style.marginM * 2

    property int issues:  -1
    property int warnings: 0

    readonly property color statusColor: {
        if (issues < 0)   return Color.mOnSurfaceVariant
        if (issues > 0)   return Color.mError
        if (warnings > 0) return Color.mTertiary
        return Color.mSecondary
    }

    readonly property string statusLabel: {
        if (issues < 0)   return "Log not found"
        if (issues > 0)   return issues + " issue" + (issues > 1 ? "s" : "") +
                                 (warnings > 0 ? "  ·  " + warnings + " warning" + (warnings > 1 ? "s" : "") : "")
        if (warnings > 0) return warnings + " warning" + (warnings > 1 ? "s" : "")
        return "All systems nominal"
    }

    Component.onCompleted: statusProc.running = true

    // ── Content ──
    ColumnLayout {
        id: contentCol
        anchors {
            left:  parent.left;  right:  parent.right
            top:   parent.top
            margins: Style.marginM
        }
        spacing: 0

        // Status header
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
                width: 10; height: 10; radius: 5
                color: root.statusColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            NText {
                Layout.fillWidth: true
                text: root.statusLabel
                font.pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: root.statusColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginS
            Layout.bottomMargin: Style.marginXS
            height: 1
            color: Color.mOutline
        }

        // Actions
        Repeater {
            model: [
                { label: "Run Doctor", action: "run" },
                { label: "Open Log",   action: "log" },
            ]

            delegate: Item {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                Rectangle {
                    anchors.fill: parent
                    radius: Style.radiusS
                    color: Color.mOnSurface
                    opacity: rowHover.containsMouse ? 0.07 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Style.marginS; rightMargin: Style.marginS
                    }
                    spacing: Style.marginS

                    NText {
                        Layout.fillWidth: true
                        text: modelData.label
                        font.pointSize: Style.fontSizeS
                        color: Color.mOnSurface
                    }
                }

                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        pluginApi?.closePanel(screen)
                        if      (modelData.action === "run") runProc.running = true
                        else if (modelData.action === "log") logProc.running = true
                    }
                }
            }
        }
    }

    // ── Processes ──
    Process {
        id: runProc
        command: ["stoa-doctor"]
        onRunningChanged: if (!running) statusProc.running = true
    }

    Process {
        id: logProc
        property string _log: (Quickshell.env("HOME") || "") + "/.config/stoa/doctor.log"
        command: ["kitty", "--title", "stoa-doctor", "--hold", "cat", _log]
    }

    Process {
        id: statusProc
        command: ["stoa-doctor-status"]
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
}
