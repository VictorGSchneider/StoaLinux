// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Memento Mori (Noctalia desktop widget)        ║
// ║  "Remember that you will die." — Stoic tradition             ║
// ║                                                              ║
// ║  Data backend is the existing `stoa-memento-data` shell      ║
// ║  script (reads ~/.config/stoa/memento.conf — NAME, BIRTH,    ║
// ║  LIFE_YEARS) so this widget stays UI-only. The same data     ║
// ║  feeds the legacy eww overlay (Super+M) and this widget.     ║
// ╚══════════════════════════════════════════════════════════════╝

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    // Noctalia injects these on every plugin Item.
    required property var    pluginApi
    required property var    screen
    required property string widgetId

    // Polled state (null until the first stoa-memento-data run lands).
    property var  memento: null
    readonly property bool hasData: memento !== null

    implicitWidth: 380
    implicitHeight: 320

    // ── Stoa palette (kept inline so the plugin compiles without
    //    pulling Noctalia's m-tokens — those are already Stoa via the
    //    color scheme, but this widget is also legible if someone has
    //    picked a non-Stoa scheme). ──
    readonly property color cBg       : "#211e19"
    readonly property color cBgLight  : "#2d2921"
    readonly property color cFg       : "#d4cfc4"
    readonly property color cFgDim    : "#a89f91"
    readonly property color cBronze   : "#c49a5c"
    readonly property color cOlive    : "#8a9a6c"
    readonly property color cStone    : "#6e6a62"

    // ── Card ──
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.80)
        border.color: root.cStone
        border.width: 1
        radius: 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 6

            // Title
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "MEMENTO MORI"
                color: root.cBronze
                font.family: "EB Garamond"
                font.pixelSize: 22
                font.letterSpacing: 6
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Remember that you will die."
                color: root.cFgDim
                font.family: "EB Garamond"
                font.italic: true
                font.pixelSize: 11
            }

            Item { Layout.preferredHeight: 8 }

            // Stats row — days / weeks / years
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: [
                        { label: "days",  key: "days_lived"  },
                        { label: "weeks", key: "weeks_lived" },
                        { label: "years", key: "years_lived" }
                    ]
                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        required property var modelData
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.hasData ? root.memento[modelData.key] : "—"
                            color: root.cFg
                            font.family: "EB Garamond"
                            font.pixelSize: 24
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: root.cFgDim
                            font.family: "EB Garamond"
                            font.pixelSize: 11
                            font.italic: true
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 6 }

            // Year progress
            Text {
                Layout.fillWidth: true
                color: root.cFgDim
                font.family: "EB Garamond"
                font.pixelSize: 11
                text: root.hasData
                    ? "Year " + root.memento.current_year + " — "
                      + (root.memento.year_pct).toFixed(1) + "%"
                    : "Year — —%"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                color: root.cBgLight
                radius: 2
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (root.hasData ? root.memento.year_pct / 100 : 0)
                    color: root.cBronze
                    radius: 2
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }

            // Life progress
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                color: root.cFgDim
                font.family: "EB Garamond"
                font.pixelSize: 11
                text: root.hasData
                    ? root.memento.weeks_lived + " of " + root.memento.total_weeks + " weeks"
                    : "— of — weeks"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                color: root.cBgLight
                radius: 2
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width *
                           (root.hasData && root.memento.total_weeks > 0
                                ? Math.min(1.0, root.memento.weeks_lived / root.memento.total_weeks)
                                : 0)
                    color: root.cOlive
                    radius: 2
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 6 }

            // Rotating Stoic quote (the data script consumes the next
            // quote from the playlist every time it's run; the bar/widget
            // share the same playlist so they don't repeat each other).
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.hasData ? root.memento.quote : ""
                color: root.cFg
                font.family: "EB Garamond"
                font.italic: true
                font.pixelSize: 11
                opacity: 0.85
            }
        }
    }

    // ── Data polling ──
    //
    // stoa-memento-data is cheap (~50 ms) and the underlying numeric
    // values only change once per day. The rotating quote rolls every
    // call, though — so polling every 60s gives a fresh aphorism without
    // hammering the system.
    Process {
        id: dataProc
        command: ["stoa-memento-data"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                try {
                    root.memento = JSON.parse(text);
                } catch (e) {
                    console.log("stoa-memento: JSON parse failed:", e, text);
                }
            }
        }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: dataProc.running = true
    }
}
