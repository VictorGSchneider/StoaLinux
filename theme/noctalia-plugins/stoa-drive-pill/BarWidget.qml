// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Drive Pill (Noctalia bar widget)              ║
// ║  "The wise man carries his possessions within him." — Bias   ║
// ║                                                              ║
// ║  Compact rclone status indicator for the bar. Polls          ║
// ║  stoa-drive-status every 60 s and colours the pill:         ║
// ║    ● olive   — all remotes mounted                           ║
// ║    ● gold    — some mounted, some not                        ║
// ║    ● grey    — none mounted (or no remotes configured)       ║
// ║                                                              ║
// ║  Widget is hidden when rclone is not installed.              ║
// ║  Left-click opens the stoa-drive rofi menu (mount/unmount).  ║
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

    // Hide entirely when rclone is not installed.
    visible: _available
    implicitWidth:  visible ? row.implicitWidth + Style.marginM * 2 : 0
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    property bool _available: true
    property int  total:   0
    property int  mounted: 0

    readonly property color pillColor: {
        if (total === 0)           return Color.mOnSurfaceVariant
        if (mounted === total)     return Color.mSecondary
        if (mounted > 0)           return Color.mTertiary
        return Color.mOnSurfaceVariant
    }

    readonly property string pillLabel:
        total > 0 ? "drive " + mounted + "/" + total : "drive"

    readonly property string pillTip: {
        if (!_available) return "rclone not installed"
        if (total === 0) return "No cloud drives configured — run stoa-drive to add one"
        if (mounted === total) return "All drives mounted (" + total + "/" + total + ")"
        if (mounted > 0)  return mounted + " of " + total + " drives mounted — click to manage"
        return "No drives mounted — click to mount"
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
            text: root.pillLabel
            color: root.pillColor
            font.pointSize: Style.fontSizeS
            font.weight: Font.Medium

            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    // ── Tooltip ──
    NToolTip {
        target: root
        text:   root.pillTip
    }

    // ── Click → open stoa-drive menu ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: driveMenuProc.running = true
    }

    Process {
        id: driveMenuProc
        command: ["stoa-drive"]
    }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-drive-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                try {
                    const d = JSON.parse(text);
                    root._available = d.available !== false;
                    root.total      = d.total   || 0;
                    root.mounted    = d.mounted || 0;
                } catch (e) {
                    Logger.w("stoa-drive-pill", "JSON parse failed:", e, text);
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
