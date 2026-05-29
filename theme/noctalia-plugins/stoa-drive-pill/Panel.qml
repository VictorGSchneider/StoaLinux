// Stoa Drive Pill — Panel
// Opened by left-click on the bar widget via pluginApi.togglePanel()

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

    readonly property real contentPreferredWidth:  300
    readonly property real contentPreferredHeight: Math.max(120, contentCol.implicitHeight)

    readonly property string _home: Quickshell.env("HOME") || ""

    property bool _available: true
    property int  total:   0
    property int  mounted: 0
    property var  _drives: []

    Component.onCompleted: statusProc.running = true

    // ── Content ──
    ColumnLayout {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // ── Per-drive rows ──
        Repeater {
            model: root._drives

            delegate: ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    visible: index > 0
                    Layout.fillWidth: true; height: 1; color: Color.mOutline
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68

                    ColumnLayout {
                        anchors {
                            fill: parent
                            leftMargin: Style.marginM; rightMargin: Style.marginM
                            topMargin: Style.marginS; bottomMargin: Style.marginS
                        }
                        spacing: Style.marginXS

                        // Top row: dot / name+type / mount btn / open btn
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: modelData.mounted ? Color.mSecondary : Color.mOnSurfaceVariant
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }

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

                            // Mount / Unmount
                            Item {
                                implicitWidth: 76; implicitHeight: 22
                                Rectangle {
                                    anchors.fill: parent; radius: Style.radiusS
                                    color: modelData.mounted ? Color.mErrorContainer : Color.mPrimaryContainer
                                }
                                NText {
                                    anchors.centerIn: parent
                                    text: modelData.mounted ? "Unmount" : "Mount"
                                    font.pointSize: Style.fontSizeXS
                                    color: modelData.mounted ? Color.mOnErrorContainer : Color.mOnPrimaryContainer
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.doAction(modelData.mounted ? "unmount" : "mount", modelData.name)
                                }
                            }

                            // Open (Thunar)
                            Item {
                                implicitWidth: 42; implicitHeight: 22
                                visible: modelData.mounted || modelData.cache_bytes > 0
                                Rectangle { anchors.fill: parent; radius: Style.radiusS; color: Color.mSurfaceVariant }
                                NText {
                                    anchors.centerIn: parent
                                    text: modelData.mounted ? "Open" : "Cache"
                                    font.pointSize: Style.fontSizeXS
                                    color: Color.mOnSurface
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const p = modelData.mounted
                                            ? root._home + "/Drive/" + modelData.name
                                            : root._home + "/.cache/rclone/vfs/" + modelData.name
                                        root.doOpen(p)
                                    }
                                }
                            }
                        }

                        // Cache bar row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            Rectangle {
                                Layout.fillWidth: true; height: 4; radius: 2
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

        // Empty state
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

        // Footer
        Rectangle { Layout.fillWidth: true; height: 1; color: Color.mOutline }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 0

            Repeater {
                model: [
                    { label: "Mount All",   id: "mountall"  },
                    { label: "Unmount All", id: "umountall" },
                    { label: "~/Drive",     id: "open"      },
                ]

                delegate: Item {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true

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
                            if      (modelData.id === "mountall")  mountAllProc.running  = true
                            else if (modelData.id === "umountall") umountAllProc.running = true
                            else if (modelData.id === "open")      root.doOpen(root._home + "/Drive")
                        }
                    }
                }
            }
        }
    }

    // ── Action helpers ──
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
    Process { id: openDirProc;    command: ["true"] }
    Process { id: mountAllProc;   command: ["stoa-drive", "mount-all"];   onRunningChanged: if (!running) refreshTimer.restart() }
    Process { id: umountAllProc;  command: ["stoa-drive", "unmount-all"]; onRunningChanged: if (!running) refreshTimer.restart() }

    // ── Data polling ──
    Process {
        id: statusProc
        command: ["stoa-drive-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const d = JSON.parse(text)
                    root._available = d.available !== false
                    root.total      = d.total    || 0
                    root.mounted    = d.mounted  || 0
                    root._drives    = d.drives   || []
                } catch (e) {}
            }
        }
    }
}
