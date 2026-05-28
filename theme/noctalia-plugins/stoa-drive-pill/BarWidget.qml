// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Drive Pill (Noctalia bar widget)              ║
// ║  "The wise man carries his possessions within him." — Bias   ║
// ║                                                              ║
// ║  Click opens a per-drive popup:                             ║
// ║    • Individual mount/unmount toggle per remote              ║
// ║    • VFS cache bar: % used of 1 GiB limit + file count      ║
// ║    • Open → Thunar at mount point (or cache if offline)     ║
// ║    • Footer: Mount All · Unmount All · Open ~/Drive          ║
// ║                                                              ║
// ║  Pill colours:                                               ║
// ║    ● olive — all remotes mounted                             ║
// ║    ● gold  — partial (some mounted)                          ║
// ║    ● grey  — none mounted / no remotes                       ║
// ║    hidden  — rclone not installed                            ║
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

    property var pluginApi: null

    visible: _available
    implicitWidth:  visible ? pill.implicitWidth + Style.marginM * 2 : 0
    implicitHeight: parent ? parent.height : 32

    // ── Polled state ──
    property bool _available: true
    property int  total:    0
    property int  mounted:  0
    property var  _drives:  []   // array of drive objects from stoa-drive-status

    readonly property string _home: Quickshell.env("HOME") || ""

    readonly property color pillColor: {
        if (total === 0)        return Color.mOnSurfaceVariant
        if (mounted === total)  return Color.mSecondary
        if (mounted > 0)        return Color.mTertiary
        return Color.mOnSurfaceVariant
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
            text: root.total > 0 ? "drive " + root.mounted + "/" + root.total : "drive"
            color: root.pillColor
            font.pointSize: Style.fontSizeS
            font.weight: Font.Medium
            Behavior on color { ColorAnimation { duration: 400 } }
        }
    }

    NToolTip {
        target: root
        text: !root._available      ? "rclone not installed"
              : root.total === 0    ? "No cloud drives configured"
              : root.mounted === root.total
                                    ? "All drives mounted (" + root.total + "/" + root.total + ")"
              : root.mounted > 0    ? root.mounted + " / " + root.total + " drives mounted"
                                    : "No drives mounted — click to manage"
    }

    // ── Click → popup ──
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: driveMenu.open()
    }

    // ── Drive popup ──
    Popup {
        id: driveMenu
        y: root.implicitHeight + 4
        x: Math.max(0, (root.implicitWidth - width) / 2)
        width: 300
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

            // ── Per-drive rows ──
            Repeater {
                model: root._drives

                delegate: ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0

                    // Separator between drives
                    Rectangle {
                        visible: index > 0
                        Layout.fillWidth: true; height: 1; color: Color.mOutline
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64

                        ColumnLayout {
                            anchors {
                                fill: parent
                                leftMargin: Style.marginM; rightMargin: Style.marginM
                                topMargin: Style.marginS; bottomMargin: Style.marginS
                            }
                            spacing: Style.marginXS

                            // ── Top row: name / type / status / actions ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginS

                                // Status dot
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: modelData.mounted ? Color.mSecondary : Color.mOnSurfaceVariant
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }

                                // Name + type
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    NText {
                                        text: modelData.name
                                        font.pointSize: Style.fontSizeS
                                        font.weight: Font.Medium
                                        color: Color.mOnSurface
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    NText {
                                        text: modelData.type
                                        font.pointSize: Style.fontSizeXS
                                        color: Color.mOnSurfaceVariant
                                    }
                                }

                                // Mount / Unmount button
                                Item {
                                    implicitWidth: 76; implicitHeight: 22

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.radiusS
                                        color: modelData.mounted
                                            ? Color.mErrorContainer
                                            : Color.mPrimaryContainer
                                    }
                                    NText {
                                        anchors.centerIn: parent
                                        text: modelData.mounted ? "Unmount" : "Mount"
                                        font.pointSize: Style.fontSizeXS
                                        color: modelData.mounted
                                            ? Color.mOnErrorContainer
                                            : Color.mOnPrimaryContainer
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.doAction(
                                            modelData.mounted ? "unmount" : "mount",
                                            modelData.name)
                                    }
                                }

                                // Open button (Thunar — mount point if mounted, else cache)
                                Item {
                                    implicitWidth: 42; implicitHeight: 22
                                    visible: modelData.mounted || modelData.cache_bytes > 0

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.radiusS
                                        color: Color.mSurfaceVariant
                                    }
                                    NText {
                                        anchors.centerIn: parent
                                        text: modelData.mounted ? "Open" : "Cache"
                                        font.pointSize: Style.fontSizeXS
                                        color: Color.mOnSurface
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = modelData.mounted
                                                ? root._home + "/Drive/" + modelData.name
                                                : root._home + "/.cache/rclone/vfs/" + modelData.name
                                            root.doOpen(p)
                                        }
                                    }
                                }
                            }

                            // ── Bottom row: cache bar ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginS

                                // Progress bar (cache % of 1 GiB limit)
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 4; radius: 2
                                    color: Color.mSurfaceVariant

                                    Rectangle {
                                        width: parent.width * Math.min(1, modelData.cache_pct / 100)
                                        height: parent.height; radius: parent.radius
                                        color: Color.mTertiary
                                        Behavior on width { NumberAnimation { duration: 300 } }
                                    }
                                }

                                NText {
                                    text: modelData.cache_pct + "%"
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }

                                NText {
                                    visible: modelData.cache_bytes > 0
                                    text: modelData.cache_human + "  ·  " +
                                          modelData.cache_files + " file" +
                                          (modelData.cache_files === 1 ? "" : "s")
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }

            // ── Empty state ──
            Item {
                visible: root._drives.length === 0
                Layout.fillWidth: true
                Layout.preferredHeight: 48

                NText {
                    anchors.centerIn: parent
                    text: "No cloud drives configured"
                    color: Color.mOnSurfaceVariant
                    font.pointSize: Style.fontSizeS
                    font.italic: true
                }
            }

            // ── Footer actions ──
            Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                spacing: 0

                Repeater {
                    model: [
                        { label: "Mount All",    id: "mountall"  },
                        { label: "Unmount All",  id: "umountall" },
                        { label: "~/Drive",      id: "open"      },
                    ]

                    delegate: Item {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Vertical divider between actions
                        Rectangle {
                            visible: index > 0
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 1; color: Color.mOutline
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Color.mOnSurface
                            opacity: footerHover.containsMouse ? 0.07 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        NText {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pointSize: Style.fontSizeXS
                            font.weight: Font.Medium
                            color: Color.mOnSurface
                        }

                        MouseArea {
                            id: footerHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                driveMenu.close()
                                if      (modelData.id === "mountall")  mountAllProc.running   = true
                                else if (modelData.id === "umountall") umountAllProc.running  = true
                                else if (modelData.id === "open")      root.doOpen(root._home + "/Drive")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Action helpers ──
    // After mount/unmount, give rclone 2 s to settle then re-poll.
    Timer { id: refreshTimer; interval: 2000; repeat: false; onTriggered: statusProc.running = true }

    function doAction(action, remote) {
        driveActionProc.command = ["stoa-drive", action, remote]
        driveActionProc.running = true
        refreshTimer.restart()
    }

    function doOpen(path) {
        openDirProc.command = ["thunar", path]
        openDirProc.running = true
    }

    // ── Processes ──
    Process { id: driveActionProc; command: ["true"] }
    Process { id: openDirProc;     command: ["true"] }
    Process { id: mountAllProc;    command: ["stoa-drive", "mount-all"];   onRunningChanged: if (!running) refreshTimer.restart() }
    Process { id: umountAllProc;   command: ["stoa-drive", "unmount-all"]; onRunningChanged: if (!running) refreshTimer.restart() }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-drive-status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root._available = d.available !== false
                    root.total      = d.total    || 0
                    root.mounted    = d.mounted  || 0
                    root._drives    = d.drives   || []
                } catch (e) {
                    Logger.w("stoa-drive-pill", "JSON parse failed:", e, text)
                }
            }
        }
    }

    Timer {
        interval: 60000; running: true; repeat: true
        onTriggered: statusProc.running = true
    }
}
