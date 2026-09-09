pragma ComponentBehavior: Bound

import QtQuick
import "../config"

/**
 * A settings line whose control is a full-width HFader. The SettingsRow control
 * slot is childrenRect-sized and cannot host a stretching track, so this row
 * wires hover, focus, the bottom seam and scroll-wheel stepping back to its
 * `surface` the same way SettingsRow does. Shared by the SOUND and DISPLAY
 * surfaces, which register it as a `scrub` row (5% per notch).
 *
 * `on` saturates the fader (SOUND passes `!muted` and the glyph turns warm when
 * off); set `iconTappable` to make the leading glyph a tap target — SOUND uses
 * it to mute that side. An empty `tip` hides the hover bubble.
 */
Item {
    id: frow

    property var surface: null
    property string label: ""
    property string icon: ""
    property real value: 0
    property bool on: true
    property bool last: false
    property bool iconTappable: false
    property string tip: ""
    property string tipDesc: ""
    property real labelWidth: 56 * frow.s

    signal moved(real v)
    signal committed(real v)
    signal iconTapped()

    readonly property real s: frow.surface ? frow.surface.s : 1
    readonly property bool focused: frow.surface ? frow.surface.focusRowItem === frow : false

    function step(d) {
        fader.step(d);
    }

    width: parent ? parent.width : 0
    height: 33 * frow.s

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2 * frow.s
        anchors.bottomMargin: 2 * frow.s
        radius: 9 * frow.s
        color: (rowHover.hovered || frow.focused) ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    HoverHandler {
        id: rowHover
        onHoveredChanged: if (frow.surface) frow.surface.reportRowHover(frow, hovered)
    }

    GlyphIcon {
        id: fi
        anchors.left: parent.left
        anchors.leftMargin: 14 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        width: 16 * frow.s
        height: 16 * frow.s
        name: frow.icon
        color: !frow.on ? Theme.vermLit : (frow.focused ? Theme.cream : Theme.subtle)
        stroke: 1.8
    }

    MouseArea {
        anchors.fill: fi
        anchors.margins: -5 * frow.s
        enabled: frow.iconTappable
        cursorShape: Qt.PointingHandCursor
        onClicked: frow.iconTapped()
    }

    Text {
        id: fl
        anchors.left: fi.right
        anchors.leftMargin: 12 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        width: frow.labelWidth
        text: frow.label
        elide: Text.ElideRight
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 12 * frow.s
        font.weight: Font.DemiBold
    }

    HFader {
        id: fader
        anchors.left: fl.right
        anchors.leftMargin: 6 * frow.s
        anchors.right: parent.right
        anchors.rightMargin: 14 * frow.s
        anchors.verticalCenter: parent.verticalCenter
        s: frow.s
        on: frow.on
        value: frow.value
        focused: frow.focused
        onMoved: (v) => frow.moved(v)
        onCommitted: (v) => frow.committed(v)
        onFocusRequested: {
            if (!frow.surface)
                return;
            frow.surface.focusRowItem = frow;
            frow.surface.kbIndex = frow.surface.rowIndexOf(frow);
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6 * frow.s
            acceptedButtons: Qt.NoButton
            property real acc: 0
            onWheel: (event) => {
                if (frow.surface) {
                    frow.surface.focusRowItem = frow;
                    frow.surface.kbIndex = frow.surface.rowIndexOf(frow);
                }
                acc += event.angleDelta.y / 120;
                const notches = Math.trunc(acc);
                if (notches !== 0) {
                    frow.step(notches * 5);
                    acc -= notches;
                }
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hairSoft
        visible: !frow.last
    }

    Tooltip {
        s: frow.s
        placement: "below"
        title: frow.tip
        desc: frow.tipDesc
        show: rowHover.hovered && frow.tip.length > 0
    }
}
