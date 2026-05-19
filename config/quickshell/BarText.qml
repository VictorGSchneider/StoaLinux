// Right-side text module for the bar. Used for disk/net/cpu/mem/clock.

import QtQuick
import "."

Text {
    color: Theme.fgDim
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    leftPadding: Theme.modulePad
    rightPadding: Theme.modulePad
    verticalAlignment: Text.AlignVCenter
    height: Theme.barHeight
}
