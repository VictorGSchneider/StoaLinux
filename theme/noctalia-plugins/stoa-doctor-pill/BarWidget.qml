// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Doctor Pill (Noctalia bar widget)             ║
// ║  "Know thyself." — inscribed at Delphi                       ║
// ║                                                              ║
// ║  Compact health indicator. Click opens an action menu:      ║
// ║    • Run Doctor  — re-run all health checks                  ║
// ║    • Open Log    — open doctor.log in kitty                  ║
// ║                                                              ║
// ║  Pill colours:                                               ║
// ║    ● olive  — all clear                                      ║
// ║    ● gold   — warnings only                                  ║
// ║    ● red    — one or more failures                           ║
// ║    ● grey   — log not yet written (first boot)               ║
// ╚══════════════════════════════════════════════════════════════╝

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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

    property string tooltipText: issues < 0 ? "Doctor log not found — run stoa-doctor"
        : issues > 0
            ? issues + " issue" + (issues > 1 ? "s" : "") +
              (warnings > 0 ? "  ·  " + warnings + " warning" + (warnings > 1 ? "s" : "") : "")
        : warnings > 0 ? warnings + " warning" + (warnings > 1 ? "s" : "")
        : "All systems nominal"

    implicitWidth:  pill.implicitWidth + Style.marginM * 2
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    property int issues:  -1   // -1 = log absent
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
            text:  root.pillLabel
            color: root.pillColor
            font.pointSize: Style.fontSizeS
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    // ── Click → popup menu ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: optionMenu.open()
    }

    // ── Option popup ──
    // Note: Popup renders via Overlay attached to the nearest Window. If the
    // bar's PanelWindow doesn't extend below the bar strip, the popup may be
    // clipped — adjust bar height in Noctalia settings if needed.
    Popup {
        id: optionMenu
        y: root.implicitHeight + 4
        x: Math.max(0, (root.implicitWidth - width) / 2)
        width: 230
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Color.mSurface
            border.color: Color.mOutline
            border.width: 1
            radius: Style.radiusS
        }

        contentItem: ColumnLayout {
            spacing: 0
            width: parent.width

            // ── Status header ──
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 44

                RowLayout {
                    anchors { fill: parent; leftMargin: Style.marginM; rightMargin: Style.marginM }
                    spacing: Style.marginS

                    Rectangle { width: 8; height: 8; radius: 4; color: root.pillColor }

                    NText {
                        Layout.fillWidth: true
                        text: root.issues < 0 ? "Log not found — not run yet"
                              : root.issues > 0
                                  ? root.issues + " issue" + (root.issues > 1 ? "s" : "") +
                                    (root.warnings > 0
                                        ? "  ·  " + root.warnings + " warning" + (root.warnings > 1 ? "s" : "")
                                        : "")
                              : root.warnings > 0
                                  ? root.warnings + " warning" + (root.warnings > 1 ? "s" : "")
                              : "All systems OK"
                        color: root.pillColor
                        font.pointSize: Style.fontSizeS
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline }

            // ── Action rows ──
            Repeater {
                model: [
                    { label: "Run Doctor",   hint: "Re-run all health checks",   id: "run" },
                    { label: "Open Log",     hint: "View doctor.log in kitty",   id: "log" },
                ]

                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46

                    // Hover tint
                    Rectangle {
                        anchors.fill: parent
                        color: Color.mOnSurface
                        opacity: hoverArea.containsMouse ? 0.07 : 0
                        radius: Style.radiusS
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    ColumnLayout {
                        anchors {
                            fill: parent
                            leftMargin: Style.marginM; rightMargin: Style.marginM
                            topMargin: Style.marginXS; bottomMargin: Style.marginXS
                        }
                        spacing: 1

                        NText {
                            text: modelData.label
                            font.pointSize: Style.fontSizeS
                            font.weight: Font.Medium
                            color: Color.mOnSurface
                        }
                        NText {
                            text: modelData.hint
                            font.pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: hoverArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            optionMenu.close()
                            if      (modelData.id === "run") runDoctorProc.running = true
                            else if (modelData.id === "log") openLogProc.running   = true
                        }
                    }
                }
            }
        }
    }

    // ── Processes ──
    Process {
        id: runDoctorProc
        command: ["stoa-doctor"]
        onRunningChanged: if (!running) statusProc.running = true   // refresh pill after run
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
                } catch (e) {
                    Logger.w("stoa-doctor-pill", "JSON parse failed:", e, text)
                }
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: statusProc.running = true
    }
}
