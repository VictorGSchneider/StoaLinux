// Stoa Health — Bar Widget
// Icon-only capsule, colored by the worst of: doctor issues/warnings,
// failed units, CPU/GPU temps, disk and memory pressure.
// Left-click  → toggle Panel (Vitals / Snapshots / Maintenance)
// Right-click → context menu (Run Doctor / Snapshot Now / Open Log)
//
// All actions launch via Quickshell.execDetached so they survive panel
// close and Quickshell restarts — Process objects die with their QML
// parent, which is why actions in the old plugins never ran.

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

    // ── User settings (Settings.qml / manifest defaults) ──
    readonly property string cfgIcon:     pluginApi?.pluginSettings?.icon ?? "heart"
    readonly property string cfgTerminal: pluginApi?.pluginSettings?.terminal ?? "kitty"
    readonly property int    cfgPollMs:   (pluginApi?.pluginSettings?.pollSeconds ?? 30) * 1000
    readonly property bool   cfgBadge:    pluginApi?.pluginSettings?.showBadge ?? true
    readonly property bool   cfgPulse:    pluginApi?.pluginSettings?.pulse ?? true

    implicitWidth:  capsule.implicitWidth + Style.marginM * 2
    implicitHeight: parent ? parent.height : 32

    // ── Aggregate state (fed by stoa-vitals-status) ──
    property int  doctorIssues:   -1
    property int  doctorWarnings:  0
    property int  failedUnits:     0
    property real cpuTempC:        0
    property real gpuTempC:        0
    property real memUsedPct:      0
    property int  diskUsedPct:     0
    property int  updates:         0

    readonly property string severity: {
        if (doctorIssues > 0 || failedUnits > 0) return "error"
        if (cpuTempC >= 90 || gpuTempC >= 90 || diskUsedPct >= 95) return "error"
        if (doctorIssues < 0) return "unknown"
        if (doctorWarnings > 0 || cpuTempC >= 80 || gpuTempC >= 80
            || diskUsedPct >= 85 || memUsedPct >= 90 || updates >= 50) return "warn"
        return "ok"
    }

    readonly property color healthColor: {
        switch (severity) {
            case "error":   return Color.mError
            case "warn":    return Color.mTertiary
            case "unknown": return Color.mOnSurfaceVariant
            default:        return Color.mSecondary
        }
    }

    readonly property int badgeCount: Math.max(0, doctorIssues) + failedUnits

    readonly property string tooltipText: {
        if (severity === "unknown") return "Stoa Health — run doctor to populate"
        var parts = []
        if (doctorIssues   > 0) parts.push(doctorIssues   + " issue"   + (doctorIssues   > 1 ? "s" : ""))
        if (doctorWarnings > 0) parts.push(doctorWarnings + " warning" + (doctorWarnings > 1 ? "s" : ""))
        if (failedUnits    > 0) parts.push(failedUnits    + " failed unit" + (failedUnits > 1 ? "s" : ""))
        if (cpuTempC >= 80)     parts.push("CPU " + cpuTempC.toFixed(0) + "°C")
        if (gpuTempC >= 80)     parts.push("GPU " + gpuTempC.toFixed(0) + "°C")
        if (diskUsedPct >= 85)  parts.push("disk " + diskUsedPct + "%")
        if (parts.length === 0) return "Stoa Health — all systems nominal"
        return "Stoa Health — " + parts.join("  ·  ")
    }

    // ── Helpers ──
    function runInTerm(title, cmd) {
        Quickshell.execDetached([root.cfgTerminal, "--title", title, "--hold", "sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
    }
    function runSilent(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
    }

    // ── Capsule (matches native bar widgets) ──
    Rectangle {
        anchors.centerIn: parent
        width:  capsule.implicitWidth + Style.marginS * 2
        height: 22
        radius: 11
        color:  Color.mSurfaceVariant
        opacity: 0.55
    }

    RowLayout {
        id: capsule
        anchors.centerIn: parent
        spacing: Style.marginXS

        NIcon {
            icon: root.cfgIcon
            color: root.healthColor
            pointSize: Style.fontSizeM
            Behavior on color { ColorAnimation { duration: 400 } }

            SequentialAnimation on opacity {
                running: root.cfgPulse && (root.severity === "error" || root.severity === "warn")
                loops: Animation.Infinite
                onRunningChanged: if (!running) parent.opacity = 1.0
                NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        // Issue-count badge — only when something is wrong
        Rectangle {
            visible: root.cfgBadge && root.badgeCount > 0
            implicitWidth: Math.max(14, badgeText.implicitWidth + 6)
            implicitHeight: 14
            radius: 7
            color: Color.mError

            NText {
                id: badgeText
                anchors.centerIn: parent
                text: root.badgeCount > 9 ? "9+" : "" + root.badgeCount
                font.pointSize: Style.fontSizeXXS !== undefined ? Style.fontSizeXXS : Style.fontSizeXS
                font.weight: Font.Bold
                color: Color.mOnError
            }
        }
    }

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
            { "label": "Run Doctor",   "action": "doctor",   "icon": "refresh" },
            { "label": "Snapshot Now", "action": "snapshot", "icon": "save" },
            { "label": "Open Log",     "action": "log",      "icon": "file-text" },
            { "label": "Settings",     "action": "settings", "icon": "settings" },
        ]
        onTriggered: function(action, item) {
            contextMenu.close()
            PanelService.closeContextMenu(screen)
            if (action === "doctor")
                root.runInTerm("stoa-doctor", root._bin + "/stoa-doctor")
            else if (action === "snapshot")
                root.runSilent(root._bin + "/stoa-pkg-snapshot && notify-send 'Stoa Health' 'Package snapshot saved'")
            else if (action === "log")
                root.runInTerm("stoa-doctor log", "cat " + root._home + "/.config/stoa/doctor.log")
            else if (action === "settings" && pluginApi?.manifest)
                BarService.openPluginSettings(screen, pluginApi.manifest)
        }
    }

    // ── Polling ──
    Process {
        id: statusProc
        command: [root._bin + "/stoa-vitals-status"]
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
        interval: root.cfgPollMs; running: true; repeat: true
        onTriggered: { statusProc.running = false; statusProc.running = true }
    }
}
