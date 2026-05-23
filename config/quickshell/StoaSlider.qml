// Minimal Stoa-themed horizontal slider. Used by the Quick Settings
// panel for Volume and Brightness. Emits `moved(value)` whenever the
// user drags or clicks the track — does NOT update `value` itself,
// so the caller is in charge of pushing the new value back after the
// underlying daemon (wpctl, brightnessctl, …) confirms it.

import QtQuick
import "."

Item {
    id: root
    property real value: 0          // 0..1
    property color trackColor: Theme.bg
    property color fillColor: Theme.bronze
    signal moved(real newValue)

    implicitHeight: 22

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 6
        radius: 3
        color: root.trackColor
        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Math.max(0, parent.width * root.value)
            radius: 3
            color: root.fillColor
            Behavior on width { NumberAnimation { duration: 80 } }
        }
    }

    Rectangle {
        id: thumb
        width: 12; height: 12
        radius: 6
        color: Theme.fg
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(root.width - width,
                                root.value * root.width - width / 2))
        Behavior on x { NumberAnimation { duration: 80 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: function(m) { _emit(m.x) }
        onPositionChanged: function(m) { if (pressed) _emit(m.x) }
        function _emit(px) {
            const v = Math.max(0, Math.min(1, px / root.width));
            root.moved(v);
        }
    }
}
