// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Memento Mori (Noctalia desktop widget)        ║
// ║  "Remember that you will die." — Stoic tradition             ║
// ║                                                              ║
// ║  Data backend is the existing `stoa-memento-data` shell      ║
// ║  script (reads ~/.config/stoa/memento.conf — NAME, BIRTH,    ║
// ║  LIFE_YEARS). Same JSON contract the eww overlay uses.       ║
// ║                                                              ║
// ║  Root is DraggableDesktopWidget per the Noctalia plugin      ║
// ║  contract (auto-handles drag/resize/edit-mode); colours come ║
// ║  from Color.m* so the active color scheme (Stoa) drives the  ║
// ║  palette.                                                    ║
// ╚══════════════════════════════════════════════════════════════╝

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets

DraggableDesktopWidget {
    id: root

    property var pluginApi: null

    readonly property real _width:  Math.round(380 * widgetScale)
    readonly property real _height: Math.round(320 * widgetScale)

    implicitWidth:  _width
    implicitHeight: _height

    // ── Polled state ──
    property var  memento: null
    readonly property bool hasData: memento !== null

    // ── Card ──
    Rectangle {
        anchors.fill: parent
        color: Color.mSurface
        opacity: 0.85
        radius: Style.radiusM
        border.color: Color.mOutline
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginS

            // Title
            NText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "MEMENTO MORI"
                color: Color.mPrimary
                font.pointSize: Style.fontSizeXL * widgetScale
                font.letterSpacing: 6
                font.weight: Font.Medium
            }
            NText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Remember that you will die."
                color: Color.mOnSurfaceVariant
                font.italic: true
                font.pointSize: Style.fontSizeS * widgetScale
            }

            Item { Layout.preferredHeight: Style.marginM }

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
                        NText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.hasData ? root.memento[modelData.key] : "—"
                            color: Color.mOnSurface
                            font.pointSize: Style.fontSizeXXL * widgetScale
                            font.weight: Font.Medium
                        }
                        NText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            color: Color.mOnSurfaceVariant
                            font.italic: true
                            font.pointSize: Style.fontSizeS * widgetScale
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: Style.marginS }

            // Year progress
            NText {
                Layout.fillWidth: true
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS * widgetScale
                text: root.hasData
                    ? "Year " + root.memento.current_year + " — "
                      + (root.memento.year_pct).toFixed(1) + "%"
                    : "Year — —%"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                color: Color.mSurfaceVariant
                radius: 2
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (root.hasData ? root.memento.year_pct / 100 : 0)
                    color: Color.mPrimary
                    radius: 2
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }

            // Life progress
            NText {
                Layout.fillWidth: true
                Layout.topMargin: Style.marginS
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeS * widgetScale
                text: root.hasData
                    ? root.memento.weeks_lived + " of " + root.memento.total_weeks + " weeks"
                    : "— of — weeks"
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                color: Color.mSurfaceVariant
                radius: 2
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width *
                           (root.hasData && root.memento.total_weeks > 0
                                ? Math.min(1.0, root.memento.weeks_lived / root.memento.total_weeks)
                                : 0)
                    color: Color.mSecondary
                    radius: 2
                    Behavior on width { NumberAnimation { duration: 300 } }
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: Style.marginS }

            // Rotating Stoic quote
            NText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.hasData ? root.memento.quote : ""
                color: Color.mOnSurface
                font.italic: true
                font.pointSize: Style.fontSizeS * widgetScale
                opacity: 0.85
            }
        }
    }

    // ── Data polling ──
    // stoa-memento-data is cheap (~50 ms); poll every 60s — short enough
    // for the quote to rotate frequently, infrequent enough not to thrash.
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
                    Logger.w("stoa-memento", "JSON parse failed:", e, text);
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
