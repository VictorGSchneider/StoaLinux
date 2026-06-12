// Stoa Health — Panel
// Three tabs: Vitals / Snapshots / Maintenance.
//
// Action lists are user-configurable through Settings.qml:
//   pluginSettings.actions = [
//     { id, tab: "vitals"|"snap"|"maint", label, icon, visible }
//   ]
// The Panel reads pluginSettings.actions, filters by tab+visible,
// preserves the user's order, and dispatches by id.
//
// Every action runs through Quickshell.execDetached, dispatched BEFORE
// closePanel() — closing the panel destroys the QML tree synchronously,
// and any execDetached call after that point silently no-ops. Order
// matters: spawn first, close second.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var       pluginApi: null
    property ShellScreen screen

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _bin:  _home + "/.local/bin"

    readonly property string cfgIcon: pluginApi?.pluginSettings?.icon ?? "heart"
    // "pkexec" → graphical polkit prompt once per action (default, safe).
    // "sudo-n" → sudo -n, requires NOPASSWD sudoers rule for these commands.
    readonly property string cfgPrivilege: pluginApi?.pluginSettings?.privilege ?? "pkexec"
    readonly property string _sudo: cfgPrivilege === "sudo-n" ? "sudo -n " : "pkexec "

    // Manifest defaults reproduced here so the panel still works when
    // pluginSettings.actions is absent (first run, before any save).
    readonly property var _defaultActions: [
        { "id": "doctor",     "tab": "vitals", "label": "Run Doctor",                "icon": "refresh",   "visible": true },
        { "id": "log",        "tab": "vitals", "label": "Log",                       "icon": "file-text", "visible": true },
        { "id": "journal",    "tab": "vitals", "label": "Journal",                   "icon": "terminal",  "visible": true },
        { "id": "pkgsnap",    "tab": "snap",   "label": "Snapshot packages now",     "icon": "save",      "visible": true },
        { "id": "backup",     "tab": "snap",   "label": "Backup configs now",        "icon": "save",      "visible": true },
        { "id": "lspkg",      "tab": "snap",   "label": "Browse snapshots",          "icon": "folder",    "visible": true },
        { "id": "lsbk",       "tab": "snap",   "label": "Browse backups",            "icon": "folder",    "visible": true },
        { "id": "updAll",     "tab": "maint",  "label": "Update all (pacman + AUR)", "icon": "download",  "visible": true },
        { "id": "updSys",     "tab": "maint",  "label": "Update system (pacman)",    "icon": "download",  "visible": true },
        { "id": "updAur",     "tab": "maint",  "label": "Update AUR (yay)",          "icon": "download",  "visible": true },
        { "id": "cleanDry",   "tab": "maint",  "label": "Cleanup (dry run)",         "icon": "trash",     "visible": true },
        { "id": "cleanApply", "tab": "maint",  "label": "Cleanup (apply)",           "icon": "trash",     "visible": true },
        { "id": "sched",      "tab": "maint",  "label": "Toggle boot schedule",      "icon": "clock",     "visible": true },
        { "id": "fw",         "tab": "maint",  "label": "Firewall (locksmith)",      "icon": "shield",    "visible": true }
    ]
    readonly property var _allActions: pluginApi?.pluginSettings?.actions ?? _defaultActions
    function _actionsForTab(t) {
        var out = []
        for (var i = 0; i < _allActions.length; i++) {
            var a = _allActions[i]
            if (a.tab === t && a.visible !== false) out.push(a)
        }
        return out
    }

    readonly property real contentPreferredWidth:  380
    readonly property real contentPreferredHeight: header.implicitHeight
                                                 + tabs.implicitHeight
                                                 + (stack.children[root.currentTab]
                                                    ? stack.children[root.currentTab].implicitHeight : 0)
                                                 + Style.marginM * 4

    // ── Aggregated status (from stoa-vitals-status) ──
    property int    doctorIssues:   -1
    property int    doctorWarnings:  0
    property real   cpuTempC:        0
    property real   cpuLoadPct:      0
    property real   gpuTempC:        0
    property real   memUsedPct:      0
    property real   memUsedGiB:      0
    property real   memTotalGiB:     0
    property int    diskUsedPct:     0
    property real   diskFreeGiB:     0
    property int    failedUnits:     0
    property int    updates:         0
    property string uptimeStr:       "—"
    property int    snapshotCount:   0
    property int    backupCount:     0
    property bool   scheduled:       false

    property int    currentTab: 0

    readonly property color statusColor: {
        if (doctorIssues   < 0) return Color.mOnSurfaceVariant
        if (doctorIssues   > 0 || failedUnits > 0
            || cpuTempC   >= 90 || gpuTempC >= 90 || diskUsedPct >= 95) return Color.mError
        if (doctorWarnings > 0 || cpuTempC >= 80 || gpuTempC >= 80
            || diskUsedPct >= 85 || memUsedPct >= 90) return Color.mTertiary
        return Color.mSecondary
    }

    readonly property string statusLabel: {
        if (doctorIssues < 0) return "Doctor not yet run"
        if (doctorIssues > 0 || failedUnits > 0)
            return (doctorIssues + failedUnits) + " issue"
                 + ((doctorIssues + failedUnits) > 1 ? "s" : "")
        if (doctorWarnings > 0) return doctorWarnings + " warning" + (doctorWarnings > 1 ? "s" : "")
        return "All systems nominal"
    }

    Component.onCompleted: statusProc.running = true

    // ── Helpers ──
    // All actions are wrapped in a single sh -c that:
    //   1. fires a "Running" notification
    //   2. runs the command silently
    //   3. fires "Done" or "Failed" depending on exit code
    // This runs detached so it survives the panel closing. The panel
    // closes AFTER execDetached returns — if the order is reversed the
    // QML tree gets destroyed mid-call and the spawn silently no-ops.
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
        if (pluginApi) pluginApi.closePanel(screen)
    }
    // Fire-and-forget without notifications (opening file managers etc.)
    function _runOpen(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
        if (pluginApi) pluginApi.closePanel(screen)
    }

    function runAction(id) {
        switch (id) {
            case "doctor":     return _runBg("Doctor",          _bin + "/stoa-doctor")
            case "log":        return _runOpen("xdg-open " + _home + "/.config/stoa/doctor.log")
            case "journal":    return _runOpen("xdg-open " + _home + "/.config/stoa/doctor.log")
            case "pkgsnap":    return _runBg("Package snapshot", _bin + "/stoa-pkg-snapshot")
            case "backup":     return _runBg("Backup configs",   _bin + "/stoa-maintain --backup")
            case "lspkg":      return _runOpen("xdg-open " + _home + "/.config/stoa/pkg-snapshots")
            case "lsbk":       return _runOpen("xdg-open " + _home)
            case "updAll":     return _runBg("Update all",      _sudo + "pacman -Syu --noconfirm && yay -Syu --noconfirm")
            case "updSys":     return _runBg("Update system",   _sudo + "pacman -Syu --noconfirm")
            case "updAur":     return _runBg("Update AUR",      "yay -Syu --noconfirm")
            case "cleanDry":   return _runBg("Cleanup (dry-run)", _bin + "/stoa-maintain --cleanup --dry-run")
            case "cleanApply": return _runBg("Cleanup",         _bin + "/stoa-maintain --cleanup")
            case "sched":      return _runBg("Toggle schedule", _sudo + _bin + "/stoa-maintain --schedule")
            case "fw":         return _runBg("Firewall",        _bin + "/stoa-locksmith")
        }
    }

    // Reusable action-row component (used in every tab)
    Component {
        id: actionRow
        Item {
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: 32

            Rectangle {
                anchors.fill: parent
                radius: Style.radiusS
                color: aHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            RowLayout {
                anchors { fill: parent; leftMargin: Style.marginS; rightMargin: Style.marginS }
                spacing: Style.marginS
                NIcon {
                    icon: modelData.icon
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                }
                NText {
                    Layout.fillWidth: true
                    text: modelData.label
                    font.pointSize: Style.fontSizeS
                    color: Color.mOnSurface
                }
                NIcon {
                    icon: "chevron-right"
                    pointSize: Style.fontSizeS
                    color: Color.mOnSurfaceVariant
                }
            }
            MouseArea {
                id: aHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(modelData.id)
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //   LAYOUT
    // ══════════════════════════════════════════════════════════════

    ColumnLayout {
        anchors {
            left:  parent.left;  right:  parent.right
            top:   parent.top
            margins: Style.marginM
        }
        spacing: Style.marginS

        // ── Header ──
        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Style.marginS

            NIcon {
                icon: root.cfgIcon
                color: root.statusColor
                pointSize: Style.fontSizeL
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                NText {
                    text: "Stoa Health"
                    font.pointSize: Style.fontSizeM
                    font.weight: Font.Bold
                    color: Color.mOnSurface
                }
                NText {
                    text: root.statusLabel
                    font.pointSize: Style.fontSizeXS
                    color: root.statusColor
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }

            Item {
                implicitWidth: 28; implicitHeight: 28
                Rectangle {
                    anchors.fill: parent; radius: Style.radiusS
                    color: refreshHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                NIcon {
                    anchors.centerIn: parent
                    icon: "refresh"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                }
                MouseArea {
                    id: refreshHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { statusProc.running = false; statusProc.running = true }
                }
            }

            // Settings gear (same as the panel-header gear on the
            // Clipboard History plugin)
            Item {
                implicitWidth: 28; implicitHeight: 28
                Rectangle {
                    anchors.fill: parent; radius: Style.radiusS
                    color: gearHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                NIcon {
                    anchors.centerIn: parent
                    icon: "settings"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurface
                }
                MouseArea {
                    id: gearHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (pluginApi?.manifest)
                            BarService.openPluginSettings(screen, pluginApi.manifest)
                        if (pluginApi) pluginApi.closePanel(screen)
                    }
                }
            }
        }

        // ── Tabs ──
        RowLayout {
            id: tabs
            Layout.fillWidth: true
            spacing: Style.marginXS

            Repeater {
                model: [
                    { icon: "activity", label: "Vitals",      idx: 0 },
                    { icon: "save",     label: "Snapshots",   idx: 1 },
                    { icon: "tool",     label: "Maintenance", idx: 2 },
                ]
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radiusS
                        color: root.currentTab === modelData.idx
                               ? Color.mPrimaryContainer
                               : (tabHover.containsMouse ? Color.mSurfaceVariant : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Style.marginXS
                        NIcon {
                            icon: modelData.icon
                            pointSize: Style.fontSizeS
                            color: root.currentTab === modelData.idx
                                   ? Color.mOnPrimaryContainer : Color.mOnSurfaceVariant
                        }
                        NText {
                            text: modelData.label
                            font.pointSize: Style.fontSizeXS
                            font.weight: root.currentTab === modelData.idx ? Font.Bold : Font.Normal
                            color: root.currentTab === modelData.idx
                                   ? Color.mOnPrimaryContainer : Color.mOnSurface
                        }
                    }
                    MouseArea {
                        id: tabHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = modelData.idx
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.4 }

        // ── Tab content ──
        StackLayout {
            id: stack
            Layout.fillWidth: true
            currentIndex: root.currentTab

            // ── Tab 0: Vitals ─────────────────────────────────────
            ColumnLayout {
                spacing: Style.marginXS

                // Live readings (fixed)
                Repeater {
                    model: [
                        { icon: "stethoscope", label: "Doctor",
                          value: root.doctorIssues < 0 ? "not run"
                                 : (root.doctorIssues + " issues · " + root.doctorWarnings + " warnings"),
                          warn: root.doctorIssues > 0 || root.doctorWarnings > 0 },
                        { icon: "alert-triangle", label: "Failed units",
                          value: "" + root.failedUnits, warn: root.failedUnits > 0 },
                        { icon: "cpu", label: "CPU",
                          value: (root.cpuTempC > 0 ? root.cpuTempC.toFixed(0) + " °C · " : "")
                                 + root.cpuLoadPct.toFixed(0) + " % load",
                          warn: root.cpuTempC >= 80 || root.cpuLoadPct >= 90 },
                        { icon: "device-tv", label: "GPU",
                          value: root.gpuTempC > 0 ? root.gpuTempC.toFixed(0) + " °C" : "—",
                          warn: root.gpuTempC >= 80 },
                        { icon: "database", label: "Memory",
                          value: root.memUsedGiB.toFixed(1) + " / " + root.memTotalGiB.toFixed(1)
                                 + " GiB (" + root.memUsedPct.toFixed(0) + "%)",
                          warn: root.memUsedPct >= 90 },
                        { icon: "folder", label: "Disk /",
                          value: root.diskUsedPct + "% used · " + root.diskFreeGiB + " GiB free",
                          warn: root.diskUsedPct >= 85 },
                        { icon: "download", label: "Updates",
                          value: root.updates + " pending", warn: root.updates >= 50 },
                        { icon: "clock", label: "Uptime",
                          value: root.uptimeStr, warn: false },
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NIcon {
                            icon: modelData.icon
                            pointSize: Style.fontSizeS
                            color: modelData.warn ? Color.mTertiary : Color.mOnSurfaceVariant
                        }
                        NText {
                            Layout.preferredWidth: 95
                            text: modelData.label
                            font.pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }
                        NText {
                            Layout.fillWidth: true
                            text: modelData.value
                            font.pointSize: Style.fontSizeS
                            color: modelData.warn ? Color.mTertiary : Color.mOnSurface
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline
                            opacity: 0.3; Layout.topMargin: Style.marginXS }

                // User-configurable Vitals actions
                Repeater {
                    model: root._actionsForTab("vitals")
                    delegate: actionRow
                }
            }

            // ── Tab 1: Snapshots ──────────────────────────────────
            ColumnLayout {
                spacing: Style.marginS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    Repeater {
                        model: [
                            { count: root.snapshotCount, label: "package snapshots" },
                            { count: root.backupCount,   label: "config backups" },
                        ]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 58
                            Rectangle {
                                anchors.fill: parent
                                radius: Style.radiusS
                                color: Color.mSurfaceVariant; opacity: 0.5
                            }
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                NText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "" + modelData.count
                                    font.pointSize: Style.fontSizeL
                                    font.weight: Font.Bold
                                    color: Color.mOnSurface
                                }
                                NText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: root._actionsForTab("snap")
                    delegate: actionRow
                }
            }

            // ── Tab 2: Maintenance ────────────────────────────────
            ColumnLayout {
                spacing: Style.marginXS

                // Updates summary header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NIcon {
                        icon: "download"
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurfaceVariant
                    }
                    NText {
                        Layout.fillWidth: true
                        text: "System updates"
                        font.pointSize: Style.fontSizeXS
                        font.weight: Font.Bold
                        color: Color.mOnSurfaceVariant
                    }
                    NText {
                        text: root.updates > 0 ? root.updates + " pending" : "up to date"
                        font.pointSize: Style.fontSizeXS
                        color: root.updates >= 50 ? Color.mTertiary
                             : root.updates > 0   ? Color.mOnSurface
                                                  : Color.mSecondary
                    }
                }

                // Scheduled badge
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    NIcon {
                        icon: "clock"
                        pointSize: Style.fontSizeS
                        color: root.scheduled ? Color.mSecondary : Color.mOnSurfaceVariant
                    }
                    NText {
                        Layout.fillWidth: true
                        text: root.scheduled
                              ? "Auto-cleanup at boot is enabled"
                              : "Auto-cleanup at boot is disabled"
                        font.pointSize: Style.fontSizeXS
                        color: Color.mOnSurfaceVariant
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline
                            opacity: 0.3; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

                Repeater {
                    model: root._actionsForTab("maint")
                    delegate: actionRow
                }
            }
        }
    }

    // ── Status polling ──
    Process {
        id: statusProc
        command: [root._bin + "/stoa-vitals-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root.doctorIssues   = d.doctor.issues
                    root.doctorWarnings = d.doctor.warnings
                    root.cpuTempC       = d.cpu.tempC
                    root.cpuLoadPct     = d.cpu.loadPct
                    root.gpuTempC       = d.gpu.tempC
                    root.memUsedPct     = d.memory.usedPct
                    root.memUsedGiB     = d.memory.usedGiB
                    root.memTotalGiB    = d.memory.totalGiB
                    root.diskUsedPct    = d.disk.usedPct
                    root.diskFreeGiB    = d.disk.freeGiB
                    root.failedUnits    = d.failedUnits
                    root.updates        = d.updates
                    root.uptimeStr      = d.uptime
                    root.snapshotCount  = d.snapshots
                    root.backupCount    = d.backups
                    root.scheduled      = d.scheduled
                } catch (e) {}
            }
        }
    }
}
