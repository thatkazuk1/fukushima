pragma ComponentBehavior: Bound

import QtQuick
import "../config"

/**
 * A small uppercase caption that groups the rows under it on the SOUND and
 * DISPLAY surfaces. `value` is an optional right-aligned live readout (SOUND
 * shows the current output / input level there).
 */
Item {
    id: sec

    property real s: 1
    property alias text: lbl.text
    property string value: ""

    width: parent ? parent.width : 0
    implicitHeight: lbl.implicitHeight

    Text {
        id: lbl
        leftPadding: 13 * sec.s
        topPadding: 13 * sec.s
        bottomPadding: 4 * sec.s
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * sec.s
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.3 * sec.s
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 14 * sec.s
        topPadding: 13 * sec.s
        visible: sec.value.length > 0
        text: sec.value
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 8.5 * sec.s
        font.weight: Font.Bold
        font.letterSpacing: 1 * sec.s
        font.features: ({ "tnum": 1 })
    }
}
