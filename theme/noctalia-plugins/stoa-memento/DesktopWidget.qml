// ╔══════════════════════════════════════════════════════════════╗
// ║  STOA LINUX — Memento Mori (Noctalia desktop widget)        ║
// ║  "Remember that you will die." — Stoic tradition             ║
// ║                                                              ║
// ║  Five progress bars showing how much of each natural cycle   ║
// ║  has elapsed — day, week, month, year, lifetime. Each one    ║
// ║  shows current % filled and the remaining time on the right. ║
// ║                                                              ║
// ║  Data backend: stoa-memento-data (reads                      ║
// ║  ~/.config/stoa/memento.conf for NAME / BIRTH / LIFE_YEARS). ║
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
    readonly property real _height: Math.round(380 * widgetScale)

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

            // ── Five progress rows ──
            // Each row: "Label … X% · Yd left" + thin bar below.
            Repeater {
                model: [
                    { label: "Day",   pctKey: "day_pct",   remainKey: "day_remaining",   barColor: Color.mError      },
                    { label: "Week",  pctKey: "week_pct",  remainKey: "week_remaining",  barColor: Color.mTertiary   },
                    { label: "Month", pctKey: "month_pct", remainKey: "month_remaining", barColor: Color.mPrimary    },
                    { label: "Year",  pctKey: "year_pct",  remainKey: "year_remaining",  barColor: Color.mSecondary  },
                    { label: "Life",  pctKey: "life_pct",  remainKey: "life_remaining",  barColor: Color.mOnSurfaceVariant }
                ]
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: index === 0 ? 0 : Style.marginXS
                    required property int index
                    required property var modelData
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS
                        NText {
                            text: modelData.label
                            color: Color.mOnSurface
                            font.pointSize: Style.fontSizeM * widgetScale
                            font.weight: Font.Medium
                        }
                        Item { Layout.fillWidth: true }
                        NText {
                            text: root.hasData
                                  ? root.memento[modelData.pctKey].toFixed(0) + "%  ·  "
                                    + root.memento[modelData.remainKey] + " left"
                                  : "—"
                            color: Color.mOnSurfaceVariant
                            font.italic: true
                            font.pointSize: Style.fontSizeS * widgetScale
                        }
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
                                   (root.hasData
                                      ? Math.min(1.0, Math.max(0.0, root.memento[modelData.pctKey] / 100))
                                      : 0)
                            color: modelData.barColor
                            radius: 2
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }
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
    // The day/week/month/year fields drift continuously, so a 60s tick
    // gives a smooth-looking progress bar without being expensive.
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
