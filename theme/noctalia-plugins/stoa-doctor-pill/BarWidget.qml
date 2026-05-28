// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Doctor Pill (Noctalia bar widget)             ║
// ║  "Know thyself." — inscribed at Delphi                       ║
// ║                                                              ║
// ║  Compact status indicator for the bar. Polls                 ║
// ║  stoa-doctor-status every 60 s and colours the pill:        ║
// ║    ● olive   — all clear                                     ║
// ║    ● gold    — warnings only                                 ║
// ║    ● red     — one or more failures                          ║
// ║    ● grey    — log not yet written (first boot)              ║
// ║                                                              ║
// ║  Left-click opens ~/.config/stoa/doctor.log in kitty.       ║
// ╚══════════════════════════════════════════════════════════════╝

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null

    implicitWidth:  row.implicitWidth + Style.marginM * 2
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    // issues == -1  → log absent (unknown)
    property int issues:  -1
    property int warnings: 0

    readonly property color pillColor: {
        if (issues < 0)  return Color.mOnSurfaceVariant
        if (issues > 0)  return Color.mError
        if (warnings > 0) return Color.mTertiary
        return Color.mSecondary
    }

    readonly property string pillTip: {
        if (issues < 0)  return "Doctor log not found — run stoa-doctor"
        if (issues > 0)  return issues + " issue" + (issues > 1 ? "s" : "") +
                                (warnings > 0 ? ", " + warnings + " warning" + (warnings > 1 ? "s" : "") : "")
        if (warnings > 0) return warnings + " warning" + (warnings > 1 ? "s" : "")
        return "All systems nominal"
    }

    // ── Pill ──
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Style.marginXS

        Rectangle {
            width:  10
            height: 10
            radius: 5
            color:  root.pillColor

            Behavior on color { ColorAnimation { duration: 400 } }
        }

        NText {
            text: "doctor"
            color: root.pillColor
            font.pointSize: Style.fontSizeS
            font.weight: Font.Medium

            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    // ── Tooltip ──
    NToolTip {
        target:  root
        text:    root.pillTip
    }

    // ── Click → open log ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: openLogProc.running = true
    }

    Process {
        id: openLogProc
        command: ["kitty", "--title", "stoa-doctor", "--hold",
                  "cat", Qt.resolvedUrl("file://" + (Quickshell.env("HOME") || "") +
                         "/.config/stoa/doctor.log").toString().replace("file://", "")]
    }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-doctor-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                try {
                    const d = JSON.parse(text);
                    root.issues   = (d.issues   !== undefined) ? d.issues   : -1;
                    root.warnings = (d.warnings !== undefined) ? d.warnings :  0;
                } catch (e) {
                    Logger.w("stoa-doctor-pill", "JSON parse failed:", e, text);
                }
            }
        }
    }

    Timer {
        interval: 60000
        running:  true
        repeat:   true
        onTriggered: statusProc.running = true
    }
}
