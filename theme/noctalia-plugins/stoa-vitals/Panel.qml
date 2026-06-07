// Stoa Vitals — Panel
// Opened by left-click on the bar widget via pluginApi.togglePanel()
//
// Three tabs (Plugin-Manager style):
//   1. Vitals       — live doctor + sensors snapshot
//   2. Snapshots    — package & config backups
//   3. Maintenance  — cleanup actions + boot schedule

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

    readonly property real contentPreferredWidth:  380
    readonly property real contentPreferredHeight: header.implicitHeight
                                                 + tabs.implicitHeight
                                                 + stack.currentItem.implicitHeight
                                                 + Style.marginM * 3

    // ── Aggregated status (from stoa-vitals-status) ──
    property int    doctorIssues:   -1
    property int    doctorWarnings:  0
    property string doctorLog:       (Quickshell.env("HOME") || "") + "/.config/stoa/doctor.log"
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

    property int    currentTab: 0   // 0 = vitals, 1 = snapshots, 2 = maintenance

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

    // ══════════════════════════════════════════════════════════════
    //   LAYOUT
    // ══════════════════════════════════════════════════════════════

    ColumnLayout {
        id: outer
        anchors {
            left:  parent.left;  right:  parent.right
            top:   parent.top
            margins: Style.marginM
        }
        spacing: Style.marginS

        // ── Header (status pill + refresh) ──
        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
                width: 12; height: 12; radius: 6
                color: root.statusColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                NText {
                    text: "Stoa Vitals"
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

            // Refresh
            Item {
                implicitWidth: 64; implicitHeight: 24
                Rectangle {
                    anchors.fill: parent; radius: Style.radiusS
                    color: refreshHover.containsMouse ? Color.mPrimaryContainer : Color.mSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                NText {
                    anchors.centerIn: parent
                    text: "Refresh"
                    font.pointSize: Style.fontSizeXS
                    color: Color.mOnSurface
                }
                MouseArea {
                    id: refreshHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: statusProc.running = true
                }
            }
        }

        // ── Tab bar (Installed/Available/Sources style) ──
        RowLayout {
            id: tabs
            Layout.fillWidth: true
            spacing: Style.marginXS

            Repeater {
                model: [
                    { label: "Vitals",      idx: 0 },
                    { label: "Snapshots",   idx: 1 },
                    { label: "Maintenance", idx: 2 },
                ]
                delegate: Item {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.radiusS
                        color: root.currentTab === modelData.idx
                               ? Color.mPrimaryContainer
                               : (tabHover.containsMouse ? Color.mSurfaceVariant : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    NText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pointSize: Style.fontSizeS
                        font.weight: root.currentTab === modelData.idx ? Font.Bold : Font.Normal
                        color: root.currentTab === modelData.idx
                               ? Color.mOnPrimaryContainer
                               : Color.mOnSurface
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
                implicitHeight: vitalsCol.implicitHeight
                ColumnLayout {
                    id: vitalsCol
                    Layout.fillWidth: true
                    spacing: Style.marginXS

                    // metric rows
                    Repeater {
                        model: [
                            { label: "Doctor",       value: root.doctorIssues < 0
                                                     ? "not run"
                                                     : (root.doctorIssues + " issues · "
                                                        + root.doctorWarnings + " warnings"),
                                                     warn: root.doctorIssues > 0
                                                        || root.doctorWarnings > 0 },
                            { label: "Failed units", value: root.failedUnits + "",
                                                     warn: root.failedUnits > 0 },
                            { label: "CPU temp",     value: root.cpuTempC > 0
                                                     ? root.cpuTempC.toFixed(0) + " °C" : "—",
                                                     warn: root.cpuTempC >= 80 },
                            { label: "CPU load",     value: root.cpuLoadPct.toFixed(0) + " %",
                                                     warn: root.cpuLoadPct >= 90 },
                            { label: "GPU temp",     value: root.gpuTempC > 0
                                                     ? root.gpuTempC.toFixed(0) + " °C" : "—",
                                                     warn: root.gpuTempC >= 80 },
                            { label: "Memory",       value: root.memUsedGiB.toFixed(1)
                                                            + " / " + root.memTotalGiB.toFixed(1)
                                                            + " GiB (" + root.memUsedPct.toFixed(0) + "%)",
                                                     warn: root.memUsedPct >= 90 },
                            { label: "Disk /",       value: root.diskUsedPct + "% used · "
                                                            + root.diskFreeGiB + " GiB free",
                                                     warn: root.diskUsedPct >= 85 },
                            { label: "Updates",      value: root.updates + " pending",
                                                     warn: root.updates >= 50 },
                            { label: "Uptime",       value: root.uptimeStr, warn: false },
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Style.marginS
                            NText {
                                Layout.preferredWidth: 110
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

                    // Actions
                    Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline
                                opacity: 0.3; Layout.topMargin: Style.marginXS }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginXS

                        Repeater {
                            model: [
                                { label: "Run Doctor",  action: "doctor" },
                                { label: "Open Log",    action: "log" },
                                { label: "Journal",     action: "journal" },
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
                                NText {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurface
                                }
                                MouseArea {
                                    id: vHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.action === "doctor")
                                            { pluginApi?.closePanel(screen); runDoctorProc.running = true }
                                        else if (modelData.action === "log")
                                            { pluginApi?.closePanel(screen); openDoctorLogProc.running = true }
                                        else if (modelData.action === "journal")
                                            { pluginApi?.closePanel(screen); openJournalProc.running = true }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab 1: Snapshots ──────────────────────────────────
            ColumnLayout {
                spacing: Style.marginS
                implicitHeight: snapCol.implicitHeight
                ColumnLayout {
                    id: snapCol
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    // Counters
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        Item {
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
                                    text: root.snapshotCount + ""
                                    font.pointSize: Style.fontSizeL
                                    font.weight: Font.Bold
                                    color: Color.mOnSurface
                                }
                                NText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "package snapshots"
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                        }

                        Item {
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
                                    text: root.backupCount + ""
                                    font.pointSize: Style.fontSizeL
                                    font.weight: Font.Bold
                                    color: Color.mOnSurface
                                }
                                NText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "config backups"
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                        }
                    }

                    // Action rows
                    Repeater {
                        model: [
                            { label: "Snapshot packages now",  action: "pkg",     icon: "save" },
                            { label: "Backup configs now",     action: "backup",  icon: "save" },
                            { label: "Browse snapshots",       action: "lspkg",   icon: "folder" },
                            { label: "Browse backups",         action: "lsbk",    icon: "folder" },
                        ]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            Rectangle {
                                anchors.fill: parent
                                radius: Style.radiusS
                                color: sHover.containsMouse ? Color.mPrimaryContainer
                                                            : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: Style.marginS; rightMargin: Style.marginS }
                                NText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeS
                                    color: Color.mOnSurface
                                }
                                NText {
                                    text: "›"
                                    font.pointSize: Style.fontSizeM
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                            MouseArea {
                                id: sHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pluginApi?.closePanel(screen)
                                    if      (modelData.action === "pkg")    pkgSnapProc.running     = true
                                    else if (modelData.action === "backup") backupProc.running      = true
                                    else if (modelData.action === "lspkg")  browseSnapshotsProc.running = true
                                    else if (modelData.action === "lsbk")   browseBackupsProc.running   = true
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab 2: Maintenance ────────────────────────────────
            ColumnLayout {
                spacing: Style.marginS
                implicitHeight: maintCol.implicitHeight
                ColumnLayout {
                    id: maintCol
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    // ── Updates header ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NText {
                            Layout.fillWidth: true
                            text: "System updates"
                            font.pointSize: Style.fontSizeXS
                            font.weight: Font.Bold
                            color: Color.mOnSurfaceVariant
                        }
                        NText {
                            text: root.updates > 0
                                  ? root.updates + " pending"
                                  : "up to date"
                            font.pointSize: Style.fontSizeXS
                            color: root.updates >= 50 ? Color.mTertiary
                                 : root.updates > 0   ? Color.mOnSurface
                                                      : Color.mSecondary
                        }
                    }

                    // ── Update buttons ──
                    Repeater {
                        model: [
                            { label: "Update all (pacman + AUR)", action: "updAll" },
                            { label: "Update system (pacman)",    action: "updSys" },
                            { label: "Update AUR (yay)",          action: "updAur" },
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
                                NText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeS
                                    color: Color.mOnSurface
                                }
                                NText {
                                    text: "›"
                                    font.pointSize: Style.fontSizeM
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                            MouseArea {
                                id: uHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pluginApi?.closePanel(screen)
                                    if      (modelData.action === "updAll") updateAllProc.running = true
                                    else if (modelData.action === "updSys") updateSysProc.running = true
                                    else if (modelData.action === "updAur") updateAurProc.running = true
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.3 }

                    // Scheduled status badge
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        Rectangle {
                            width: 10; height: 10; radius: 5
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline; opacity: 0.3 }

                    // Action rows
                    Repeater {
                        model: [
                            { label: "Cleanup (dry run)",     action: "dry",      hint: "preview" },
                            { label: "Cleanup (apply)",       action: "apply",    hint: "destructive" },
                            { label: root.scheduled
                                     ? "Disable boot schedule"
                                     : "Enable boot schedule", action: "sched",  hint: "" },
                            { label: "Firewall (locksmith)",  action: "fw",       hint: "" },
                        ]
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36

                            Rectangle {
                                anchors.fill: parent
                                radius: Style.radiusS
                                color: mHover.containsMouse ? Color.mPrimaryContainer
                                                            : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            RowLayout {
                                anchors { fill: parent; leftMargin: Style.marginS; rightMargin: Style.marginS }
                                spacing: Style.marginS

                                NText {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.pointSize: Style.fontSizeS
                                    color: modelData.hint === "destructive"
                                           ? Color.mError : Color.mOnSurface
                                }
                                NText {
                                    visible: modelData.hint.length > 0
                                    text: modelData.hint
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                            MouseArea {
                                id: mHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    pluginApi?.closePanel(screen)
                                    if      (modelData.action === "dry")   cleanupDryProc.running   = true
                                    else if (modelData.action === "apply") cleanupApplyProc.running = true
                                    else if (modelData.action === "sched") scheduleProc.running     = true
                                    else if (modelData.action === "fw")    firewallProc.running     = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //   PROCESSES
    // ══════════════════════════════════════════════════════════════

    Process {
        id: statusProc
        command: ["stoa-vitals-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root.doctorIssues   = d.doctor.issues
                    root.doctorWarnings = d.doctor.warnings
                    root.doctorLog      = d.doctor.log
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

    // Tab 0 — Vitals
    Process {
        id: runDoctorProc
        command: ["kitty", "--title", "stoa-doctor", "--hold", "stoa-doctor"]
    }
    Process {
        id: openDoctorLogProc
        command: ["kitty", "--title", "stoa-doctor", "--hold", "cat", root.doctorLog]
    }
    Process {
        id: openJournalProc
        command: ["kitty", "--title", "journal", "--hold",
                  "sh", "-c", "journalctl -p 3..4 -b --no-pager | tail -200"]
    }

    // Tab 1 — Snapshots
    Process {
        id: pkgSnapProc
        command: ["kitty", "--title", "stoa-pkg-snapshot", "--hold", "stoa-pkg-snapshot"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: backupProc
        command: ["kitty", "--title", "stoa-maintain", "--hold", "stoa-maintain", "--backup"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: browseSnapshotsProc
        property string _dir: (Quickshell.env("HOME") || "") + "/.config/stoa/pkg-snapshots"
        command: ["xdg-open", _dir]
    }
    Process {
        id: browseBackupsProc
        property string _dir: Quickshell.env("HOME") || ""
        command: ["xdg-open", _dir]
    }

    // Tab 2 — Updates (mirrors zsh aliases update / update-aur / update-all)
    Process {
        id: updateSysProc
        command: ["kitty", "--title", "update (pacman)", "--hold",
                  "sh", "-c", "sudo pacman -Syu"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: updateAurProc
        command: ["kitty", "--title", "update-aur (yay)", "--hold",
                  "sh", "-c", "yay -Syu"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: updateAllProc
        command: ["kitty", "--title", "update-all", "--hold",
                  "sh", "-c", "sudo pacman -Syu && yay -Syu"]
        onRunningChanged: if (!running) statusProc.running = true
    }

    // Tab 2 — Maintenance
    Process {
        id: cleanupDryProc
        command: ["kitty", "--title", "stoa-maintain (dry-run)", "--hold",
                  "stoa-maintain", "--cleanup", "--dry-run"]
    }
    Process {
        id: cleanupApplyProc
        command: ["kitty", "--title", "stoa-maintain", "--hold",
                  "stoa-maintain", "--cleanup"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: scheduleProc
        command: ["kitty", "--title", "stoa-maintain (schedule)", "--hold",
                  "stoa-maintain", "--schedule"]
        onRunningChanged: if (!running) statusProc.running = true
    }
    Process {
        id: firewallProc
        command: ["kitty", "--title", "stoa-locksmith", "--hold", "stoa-locksmith"]
    }
}
