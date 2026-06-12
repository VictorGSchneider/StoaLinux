// Stoa Health — Bar Widget
// Inherits NIconButton so the bar's global config (capsule color,
// outline, size, font scale, density) applies automatically — same
// integration the official Clipboard/Plugin-Manager widgets get.
//
// Left-click  → toggle panel (Vitals / Snapshots / Maintenance)
// Right-click → Run Doctor / Snapshot Now / Open Log / Settings
//
// Background actions: every command runs through Quickshell.execDetached
// wrapped in sh -c with notify-send for Running / Done / Failed — no
// terminal is opened anywhere.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
    id: root

    // Shell-injected plugin properties
    property var    pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int    sectionWidgetIndex: -1
    property int    sectionWidgetsCount: 0

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _bin:  _home + "/.local/bin"

    // ── User settings ──
    readonly property string cfgIcon:   pluginApi?.pluginSettings?.icon ?? "heart"
    readonly property int    cfgPollMs: (pluginApi?.pluginSettings?.pollSeconds ?? 30) * 1000
    readonly property bool   cfgBadge:  pluginApi?.pluginSettings?.showBadge ?? true

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

    // ── NIconButton appearance: pick up the bar's global capsule
    //    styling, then tint the foreground with the health color ──
    icon: root.cfgIcon
    baseSize: Style.getCapsuleHeightForScreen(screen?.name)
    applyUiScale: false
    tooltipDirection: BarService.getTooltipDirection(screen?.name)
    customRadius: Style.radiusL
    colorBg: Style.capsuleColor
    colorFg: root.healthColor
    colorBgHover: Color.mHover
    colorFgHover: root.healthColor
    colorBorder: "transparent"
    colorBorderHover: "transparent"

    tooltipText: {
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

    onClicked: {
        if (!pluginApi) return
        const open = pluginApi.isPanelOpen?.(screen) === true
        if (open && pluginApi.closePanel) pluginApi.closePanel(screen)
        else if (pluginApi.openPanel)     pluginApi.openPanel(screen, root)
    }
    onRightClicked: PanelService.showContextMenu(contextMenu, root, screen)

    // ── Helpers ──
    function _runBg(label, cmd) {
        var script =
            'export PATH="$HOME/.local/bin:$PATH"; ' +
            'notify-send "Stoa Health" "Running: ' + label + '"; ' +
            'if ' + cmd + '; then ' +
            '  notify-send "Stoa Health" "Done: ' + label + '"; ' +
            'else ' +
            '  notify-send -u critical "Stoa Health" "Failed: ' + label + '"; ' +
            'fi'
        Quickshell.execDetached(["sh", "-c", script])
    }
    function _runOpen(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
    }

    // ── Badge overlay (top-right corner) ──
    Rectangle {
        visible: root.cfgBadge && root.badgeCount > 0
        anchors {
            top: parent.top
            right: parent.right
            topMargin: -2
            rightMargin: -2
        }
        implicitWidth:  Math.max(14, badgeText.implicitWidth + 6)
        implicitHeight: 14
        radius: 7
        color: Color.mError
        z: 2

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badgeCount > 9 ? "9+" : "" + root.badgeCount
            font.pointSize: Style.fontSizeXS
            font.weight: Font.Bold
            color: Color.mOnError
        }
    }

    // ── Right-click menu ──
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
            if      (action === "doctor")   root._runBg("Doctor", root._bin + "/stoa-doctor")
            else if (action === "snapshot") root._runBg("Package snapshot", root._bin + "/stoa-pkg-snapshot")
            else if (action === "log")      root._runOpen("xdg-open " + root._home + "/.config/stoa/doctor.log")
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
