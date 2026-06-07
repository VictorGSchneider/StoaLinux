// Stoa Vitals — Bar Widget
// Left-click  → toggle Panel (3 tabs: Vitals / Snapshots / Maintenance)
// Right-click → context menu (Run Doctor / Snapshot Now / Open Log)

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

    implicitWidth:  capsule.implicitWidth + Style.marginM * 2
    implicitHeight: parent ? parent.height : 32

    // ── Aggregate state ──
    property int    doctorIssues:   -1
    property int    doctorWarnings:  0
    property int    failedUnits:     0
    property real   cpuTempC:        0
    property real   gpuTempC:        0
    property real   memUsedPct:      0
    property real   diskUsedPct:     0
    property int    updates:         0

    readonly property string severity: {
        // critical → error → warn → ok
        if (doctorIssues > 0 || failedUnits > 0) return "error"
        if (cpuTempC >= 90 || gpuTempC >= 90 || diskUsedPct >= 95) return "error"
        if (doctorIssues < 0) return "unknown"
        if (doctorWarnings > 0 || cpuTempC >= 80 || gpuTempC >= 80
            || diskUsedPct >= 85 || memUsedPct >= 90 || updates >= 50) return "warn"
        return "ok"
    }

    readonly property color pillColor: {
        switch (severity) {
            case "error":   return Color.mError
            case "warn":    return Color.mTertiary
            case "unknown": return Color.mOnSurfaceVariant
            default:        return Color.mSecondary
        }
    }

    readonly property string pillLabel: {
        switch (severity) {
            case "error":   return "vitals ✕"
            case "warn":    return "vitals ⚠"
            case "unknown": return "vitals"
            default:        return "vitals"
        }
    }

    readonly property string tooltipText: {
        if (severity === "unknown") return "Run stoa-doctor to populate status"
        var parts = []
        if (doctorIssues   > 0) parts.push(doctorIssues   + " issue"   + (doctorIssues   > 1 ? "s" : ""))
        if (doctorWarnings > 0) parts.push(doctorWarnings + " warning" + (doctorWarnings > 1 ? "s" : ""))
        if (failedUnits    > 0) parts.push(failedUnits    + " failed unit" + (failedUnits > 1 ? "s" : ""))
        if (cpuTempC >= 80)     parts.push("CPU " + cpuTempC.toFixed(0) + "°C")
        if (gpuTempC >= 80)     parts.push("GPU " + gpuTempC.toFixed(0) + "°C")
        if (diskUsedPct >= 85)  parts.push("disk " + diskUsedPct + "%")
        if (parts.length === 0) return "All systems nominal"
        return parts.join("  ·  ")
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

        // Heart-shaped dot (two stacked circles + diamond — kept as a single
        // circle for simplicity; the colour itself carries the meaning).
        Rectangle {
            width: 8; height: 8; radius: 4
            color: root.pillColor
            Behavior on color { ColorAnimation { duration: 400 } }

            SequentialAnimation on opacity {
                running: root.severity === "error" || root.severity === "warn"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
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

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Run Doctor",     "action": "doctor",   "icon": "refresh" },
            { "label": "Snapshot Now",   "action": "snapshot", "icon": "save" },
            { "label": "Open Doctor Log", "action": "log",     "icon": "file-text" },
        ]
        onTriggered: function(action, item) {
            if      (action === "doctor")   runDoctorProc.running   = true
            else if (action === "snapshot") snapshotProc.running    = true
            else if (action === "log")      openLogProc.running     = true
        }
    }

    // ── Processes ──
    Process {
        id: runDoctorProc
        command: ["stoa-doctor"]
        onRunningChanged: if (!running) statusProc.running = true
    }

    Process {
        id: snapshotProc
        command: ["stoa-pkg-snapshot"]
        onRunningChanged: if (!running) statusProc.running = true
    }

    Process {
        id: openLogProc
        property string _log: (Quickshell.env("HOME") || "") + "/.config/stoa/doctor.log"
        command: ["kitty", "--title", "stoa-doctor", "--hold", "cat", _log]
    }

    // ── Polling ──
    Process {
        id: statusProc
        command: ["stoa-vitals-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root.doctorIssues   = d.doctor.issues
                    root.doctorWarnings = d.doctor.warnings
                    root.failedUnits    = d.failedUnits
                    root.cpuTempC       = d.cpu.tempC
                    root.gpuTempC       = d.gpu.tempC
                    root.memUsedPct     = d.memory.usedPct
                    root.diskUsedPct    = d.disk.usedPct
                    root.updates        = d.updates
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30000; running: true; repeat: true
        onTriggered: { statusProc.running = false; statusProc.running = true }
    }
}
