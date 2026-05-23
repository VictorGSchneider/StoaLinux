// Quick Settings popup — opens below a trigger Item in the bar.
// Inspired by the macOS / GNOME Control Center pattern: status rows
// at the top, toggle tiles, sliders, then a media player card.
//
// All wiring is via the parent Bar's polled state + Process bindings,
// passed in as properties so this component stays UI-only.

import Quickshell
import Quickshell.Io
import QtQuick
import "."

PopupWindow {
    id: popup
    required property Item target
    required property var bar   // the parent Bar, for shared state + Process actions

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom | Edges.Left

    color: "transparent"
    visible: false
    grabFocus: true
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.bgLight
        border.color: Theme.stone
        border.width: 1
        radius: 8
        implicitWidth: 340
        implicitHeight: layout.implicitHeight + 24

        Column {
            id: layout
            x: 12; y: 12
            width: parent.width - 24
            spacing: 12

            // ── Status rows (Network · Bluetooth · Settings) ──
            Rectangle {
                width: parent.width
                radius: 6
                color: Theme.bg
                border.color: Theme.stone
                border.width: 1
                implicitHeight: rowsCol.implicitHeight + 16
                Column {
                    id: rowsCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 10

                    QSRow {
                        title: "Network"
                        subtitle: popup.bar.netDisconnected ? "Disconnected"
                                                              : popup.bar.netText.replace(/^\s+/, "")
                        glyph: ""
                        onClicked: nmtuiProc.running = true
                    }
                    QSRow {
                        title: "Bluetooth"
                        subtitle: popup.bar.bluetoothOn ? "On" : "Off"
                        glyph: ""
                        onClicked: btToggle.running = true
                    }
                    QSRow {
                        title: "Settings"
                        subtitle: "Stoa Panel"
                        glyph: ""
                        onClicked: { settingsProc.running = true; popup.visible = false; }
                    }
                }
            }

            // ── Toggle tiles ──
            Row {
                width: parent.width
                spacing: 10
                QSTile {
                    width: (parent.width - 2 * parent.spacing) / 3
                    title: "Do Not\nDisturb"
                    glyph: ""
                    active: popup.bar.dndOn
                    onClicked: dndToggle.running = true
                }
                QSTile {
                    width: (parent.width - 2 * parent.spacing) / 3
                    title: "Night\nColor"
                    glyph: ""
                    active: popup.bar.nightOn
                    onClicked: nightToggle.running = true
                }
                QSTile {
                    width: (parent.width - 2 * parent.spacing) / 3
                    title: "Lock"
                    glyph: ""
                    active: false
                    onClicked: { lockProc.running = true; popup.visible = false; }
                }
            }

            // ── Volume slider ──
            Column {
                width: parent.width
                spacing: 6
                Row {
                    width: parent.width
                    Text {
                        text: "Volume"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        width: parent.width - volPctLbl.width
                    }
                    Text {
                        id: volPctLbl
                        text: popup.bar.volumeMuted ? "muted" : popup.bar.volumePct + "%"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignRight
                    }
                }
                StoaSlider {
                    width: parent.width
                    value: popup.bar.volumeMuted ? 0 : popup.bar.volumePct / 100
                    onMoved: function(v) {
                        setVolumeProc.command = ["wpctl", "set-volume",
                                                 "@DEFAULT_AUDIO_SINK@", v.toFixed(2)];
                        setVolumeProc.running = true;
                        popup.bar.volumePct = Math.round(v * 100);
                    }
                }
            }

            // ── Brightness slider ──
            Column {
                width: parent.width
                spacing: 6
                visible: popup.bar.brightnessPct >= 0
                Row {
                    width: parent.width
                    Text {
                        text: "Display Brightness"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        width: parent.width - briPctLbl.width
                    }
                    Text {
                        id: briPctLbl
                        text: popup.bar.brightnessPct + "%"
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignRight
                    }
                }
                StoaSlider {
                    width: parent.width
                    value: popup.bar.brightnessPct / 100
                    onMoved: function(v) {
                        const pct = Math.round(v * 100);
                        setBrightnessProc.command = ["brightnessctl",
                                                     "set", pct + "%"];
                        setBrightnessProc.running = true;
                        popup.bar.brightnessPct = pct;
                    }
                }
            }

            // ── Media player ──
            Rectangle {
                width: parent.width
                radius: 6
                color: Theme.bg
                border.color: Theme.stone
                border.width: 1
                visible: popup.bar.mediaTitle.length > 0
                implicitHeight: mediaRow.implicitHeight + 16
                Row {
                    id: mediaRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 12

                    Column {
                        width: parent.width - mediaCtrls.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: popup.bar.mediaTitle
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: popup.bar.mediaArtist
                            color: Theme.fgDim
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                    Row {
                        id: mediaCtrls
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        QSGlyphButton { text: ""; onClicked: prevProc.running = true }
                        QSGlyphButton {
                            text: popup.bar.mediaPlaying ? "" : ""
                            onClicked: playPauseProc.running = true
                        }
                        QSGlyphButton { text: ""; onClicked: nextProc.running = true }
                    }
                }
            }
        }
    }

    // ── One-shot Process actions ──
    Process { id: dndToggle;         command: ["dunstctl", "set-paused", "toggle"] }
    Process { id: nightToggle;       command: ["bash", "-c",
        "pgrep -x gammastep >/dev/null && pkill gammastep || (setsid gammastep -O 3500 >/dev/null 2>&1 &)"] }
    Process { id: lockProc;          command: ["hyprlock"] }
    Process { id: settingsProc;      command: ["stoa-settings"] }
    Process { id: nmtuiProc;         command: ["kitty", "--class", "stoa-nmtui", "-e", "nmtui"] }
    Process { id: btToggle;          command: ["bash", "-c",
        "bluetoothctl show | grep -q 'Powered: yes' && bluetoothctl power off || bluetoothctl power on"] }
    Process { id: setVolumeProc;     command: ["true"] }   // command rebound on use
    Process { id: setBrightnessProc; command: ["true"] }
    Process { id: prevProc;          command: ["playerctl", "previous"] }
    Process { id: nextProc;          command: ["playerctl", "next"] }
    Process { id: playPauseProc;     command: ["playerctl", "play-pause"] }

    // ── Inline subcomponents ──
    component QSRow: Item {
        property string title
        property string subtitle
        property string glyph
        signal clicked()

        width: parent.width
        implicitHeight: 36
        Row {
            anchors.fill: parent
            spacing: 12
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28
                radius: 14
                color: rowHover.containsMouse ? Theme.bronze : Theme.bgLight
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: glyph
                    color: Theme.fg
                    font.pixelSize: 13
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text { text: title;    color: Theme.fg;    font.family: Theme.fontFamily; font.pixelSize: 12 }
                Text { text: subtitle; color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: 10 }
            }
        }
        MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component QSTile: Rectangle {
        property string title
        property string glyph
        property bool active: false
        signal clicked()

        height: 72
        radius: 6
        color: active ? Theme.bronze : Theme.bg
        border.color: tileHover.containsMouse ? Theme.bronze : Theme.stone
        border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on border.color { ColorAnimation { duration: 120 } }

        Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: glyph
                color: active ? Theme.bg : Theme.fg
                font.pixelSize: 16
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: title
                color: active ? Theme.bg : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
            }
        }
        MouseArea {
            id: tileHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component QSGlyphButton: Rectangle {
        property alias text: lbl.text
        signal clicked()
        width: 28; height: 28
        radius: 14
        color: glyphMouse.containsMouse ? Theme.bg : "transparent"
        border.color: Theme.stone
        border.width: 1
        Text {
            id: lbl
            anchors.centerIn: parent
            color: Theme.fg
            font.pixelSize: 13
        }
        MouseArea {
            id: glyphMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
