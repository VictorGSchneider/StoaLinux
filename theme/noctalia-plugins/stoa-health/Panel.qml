// Stoa Health — Panel
// Three tabs (plugin-manager style): Vitals / Snapshots / Maintenance.
//
// Every action runs through Quickshell.execDetached — never Process —
// because Process objects are destroyed (and their children killed)
// the moment the panel closes.

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

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _bin:  _home + "/.local/bin"

    readonly property string cfgIcon:     pluginApi?.pluginSettings?.icon ?? "heart"
    readonly property string cfgTerminal: pluginApi?.pluginSettings?.terminal ?? "kitty"

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
    function runInTerm(title, cmd) {
        Quickshell.execDetached([root.cfgTerminal, "--title", title, "--hold", "sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
        pluginApi?.closePanel(screen)
    }
    function runSilent(cmd) {
        Quickshell.execDetached(["sh", "-c",
            'export PATH="$HOME/.local/bin:$PATH"; ' + cmd])
        pluginApi?.closePanel(screen)
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

            // Refresh icon button
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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginXS

                    Repeater {
                        model: [
                            { icon: "refresh",   label: "Run Doctor", action: "doctor" },
                            { icon: "file-text", label: "Log",        action: "log" },
                            { icon: "terminal",  label: "Journal",    action: "journal" },
                        ]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            Rectangle {
                                anchors.fill: parent; radius: Style.radiusS
                                color: vHover.containsMouse ? Color.mPrimaryContainer
                                                            : Color.mSurfaceVariant
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Style.marginXS
                                NIcon {
                                    icon: modelData.icon
                                    pointSize: Style.fontSizeS
                                    color: Color.mOnSurface
                                }
                                NText {
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurface
                                }
                            }
                            MouseArea {
                                id: vHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.action === "doctor")
                                        root.runInTerm("stoa-doctor", root._bin + "/stoa-doctor")
                                    else if (modelData.action === "log")
                                        root.runInTerm("stoa-doctor log",
                                            "cat " + root._home + "/.config/stoa/doctor.log")
                                    else if (modelData.action === "journal")
                                        root.runInTerm("journal",
                                            "journalctl -p 3..4 -b --no-pager | tail -200")
                                }
                            }
                        }
                    }
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
                    model: [
                        { icon: "save",   label: "Snapshot packages now", action: "pkg" },
                        { icon: "save",   label: "Backup configs now",    action: "backup" },
                        { icon: "folder", label: "Browse snapshots",      action: "lspkg" },
                        { icon: "folder", label: "Browse backups",        action: "lsbk" },
                    ]
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.radiusS
                            color: sHover.containsMouse ? Color.mPrimaryContainer : "transparent"
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
                            id: sHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.action === "pkg")
                                    root.runSilent(root._bin + "/stoa-pkg-snapshot && notify-send 'Stoa Health' 'Package snapshot saved'")
                                else if (modelData.action === "backup")
                                    root.runInTerm("stoa-maintain backup",
                                        root._bin + "/stoa-maintain --backup")
                                else if (modelData.action === "lspkg")
                                    root.runSilent("xdg-open " + root._home + "/.config/stoa/pkg-snapshots")
                                else if (modelData.action === "lsbk")
                                    root.runSilent("xdg-open " + root._home)
                            }
                        }
                    }
                }
            }

            // ── Tab 2: Maintenance ────────────────────────────────
            ColumnLayout {
                spacing: Style.marginXS

                // Updates header
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

                Repeater {
                    model: [
                        { icon: "download", label: "Update all (pacman + AUR)",
                          cmd: "sudo pacman -Syu && yay -Syu", title: "update-all" },
                        { icon: "download", label: "Update system (pacman)",
                          cmd: "sudo pacman -Syu", title: "update" },
                        { icon: "download", label: "Update AUR (yay)",
                          cmd: "yay -Syu", title: "update-aur" },
                    ]
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.radiusS
                            color: uHover.containsMouse ? Color.mPrimaryContainer
                                                        : Color.mSurfaceVariant
                            opacity: uHover.containsMouse ? 1.0 : 0.5
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
                            id: uHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runInTerm(modelData.title, modelData.cmd)
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline
                            opacity: 0.3; Layout.topMargin: Style.marginXS; Layout.bottomMargin: Style.marginXS }

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

                Repeater {
                    model: [
                        { icon: "trash",  label: "Cleanup (dry run)", action: "dry",   danger: false },
                        { icon: "trash",  label: "Cleanup (apply)",   action: "apply", danger: true },
                        { icon: "clock",  label: root.scheduled
                                               ? "Disable boot schedule"
                                               : "Enable boot schedule", action: "sched", danger: false },
                        { icon: "shield", label: "Firewall (locksmith)", action: "fw",  danger: false },
                    ]
                    delegate: Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Rectangle {
                            anchors.fill: parent
                            radius: Style.radiusS
                            color: mHover.containsMouse ? Color.mPrimaryContainer : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        RowLayout {
                            anchors { fill: parent; leftMargin: Style.marginS; rightMargin: Style.marginS }
                            spacing: Style.marginS
                            NIcon {
                                icon: modelData.icon
                                pointSize: Style.fontSizeS
                                color: modelData.danger ? Color.mError : Color.mOnSurfaceVariant
                            }
                            NText {
                                Layout.fillWidth: true
                                text: modelData.label
                                font.pointSize: Style.fontSizeS
                                color: modelData.danger ? Color.mError : Color.mOnSurface
                            }
                            NIcon {
                                icon: "chevron-right"
                                pointSize: Style.fontSizeS
                                color: Color.mOnSurfaceVariant
                            }
                        }
                        MouseArea {
                            id: mHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.action === "dry")
                                    root.runInTerm("stoa-maintain (dry-run)",
                                        root._bin + "/stoa-maintain --cleanup --dry-run")
                                else if (modelData.action === "apply")
                                    root.runInTerm("stoa-maintain",
                                        root._bin + "/stoa-maintain --cleanup")
                                else if (modelData.action === "sched")
                                    root.runInTerm("stoa-maintain (schedule)",
                                        root._bin + "/stoa-maintain --schedule")
                                else if (modelData.action === "fw")
                                    root.runInTerm("stoa-locksmith",
                                        root._bin + "/stoa-locksmith")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Status polling (Process is fine here: it only reads while
    //    the panel is open, and is re-spawned on every open) ──
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
