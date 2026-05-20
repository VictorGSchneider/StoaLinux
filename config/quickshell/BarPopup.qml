// A bar tooltip-style popup. Lives in its own Wayland surface so it can
// extend below the 30px PanelWindow without being clipped (the reason
// QtQuick.Controls.ToolTip was unusable inside a thin bar).

import Quickshell
import QtQuick
import "."

PopupWindow {
    id: popup
    required property Item target
    property string content: ""
    property bool monospace: false

    anchor.item: target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    color: "transparent"
    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.bgLight
        border.color: Theme.stone
        border.width: 1
        radius: 4
        implicitWidth: label.implicitWidth + 20
        implicitHeight: label.implicitHeight + 12

        Text {
            id: label
            anchors.centerIn: parent
            text: popup.content
            color: Theme.fg
            font.family: popup.monospace ? Theme.monoFamily : Theme.fontFamily
            font.pixelSize: Theme.fontSize
            textFormat: Text.PlainText
        }
    }
}
