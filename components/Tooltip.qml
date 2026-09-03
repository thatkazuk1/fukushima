import QtQuick
import "../config"

/**
 * Washi hint bubble for pill controls. Anchored to its parent control;
 * `placement` decides whether the bubble floats above (pointer down) or below
 * (pointer up), and `align` whether its left/right edge or centre lines up
 * with the control, so bubbles near the pill edge never clip off-screen. The
 * host sets `show` from the control's own HoverHandler; the bubble arms after
 * a hover delay, fades in slowly and out fast.
 *
 * Non-interactive by design: no MouseArea or HoverHandler lives here, so it
 * never steals pointer events from the controls or the mixer's hover tracker.
 * It is `visible: false` whenever fully faded, for the same reason.
 */
Item {
    id: root

    property real s: 1
    property string title: ""
    property string desc: ""
    property bool show: false
    property string placement: "above"
    property string align: "center"

    readonly property bool below: placement === "below"
    readonly property real pointerH: 5 * s
    readonly property real gap: 5 * s

    property bool armed: false

    width: bubble.width
    height: bubble.height + pointerH
    z: 20

    // `align` selects exactly one horizontal anchor; the other two resolve to
    // undefined at runtime, so this is never a real anchor conflict.
    // qmllint disable Quick.anchor-combinations
    anchors.horizontalCenter: root.align === "center" ? parent.horizontalCenter : undefined
    anchors.left: root.align === "left" ? parent.left : undefined
    anchors.right: root.align === "right" ? parent.right : undefined
    // qmllint enable Quick.anchor-combinations
    anchors.bottom: below ? undefined : parent.top
    anchors.bottomMargin: below ? 0 : gap
    anchors.top: below ? parent.bottom : undefined
    anchors.topMargin: below ? gap : 0

    visible: armed || opacity > 0.01
    opacity: armed ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.armed ? Motion.standard : Motion.fast } }

    Timer {
        id: delay
        interval: 470
        onTriggered: root.armed = true
    }
    onShowChanged: {
        if (show) {
            delay.restart();
        } else {
            delay.stop();
            armed = false;
        }
    }

    // Soft drop shadow — a plain offset scrim, not a layer effect (the layer
    // effect was rendering the bubble itself translucent).
    Rectangle {
        anchors.fill: bubble
        anchors.topMargin: 2 * root.s
        radius: bubble.radius + 1
        color: Qt.rgba(0, 0, 0, 0.22)
        z: -1
    }

    Rectangle {
        id: bubble
        // qmllint disable Quick.anchor-combinations
        anchors.horizontalCenter: root.align === "center" ? parent.horizontalCenter : undefined
        anchors.left: root.align === "left" ? parent.left : undefined
        anchors.right: root.align === "right" ? parent.right : undefined
        // qmllint enable Quick.anchor-combinations
        anchors.top: root.below ? undefined : parent.top
        anchors.bottom: root.below ? parent.bottom : undefined
        width: Math.max(titleText.implicitWidth, descText.implicitWidth) + 18 * root.s
        height: column.implicitHeight + 11 * root.s
        radius: 8 * root.s
        // Inverted against the pill: `cream` is the copy colour, so a cream-filled
        // bubble is always maximally different from the cardTop/cardBot body
        // behind it — a light hint on the dark pill, a dark hint on the light one.
        color: Theme.cream
        border.width: 1
        border.color: Qt.alpha(Theme.cardBot, 0.25)
    }

    Column {
        id: column
        anchors.centerIn: bubble
        spacing: 2 * root.s

        Text {
            id: titleText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.title
            color: Theme.cardBot
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: Font.Bold
        }
        Text {
            id: descText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.desc.length > 0
            text: root.desc
            color: Qt.alpha(Theme.cardBot, 0.7)
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
        }
    }

    Canvas {
        id: pointer
        width: 11 * root.s
        height: root.pointerH
        // qmllint disable Quick.anchor-combinations
        anchors.horizontalCenter: root.align === "center" ? parent.horizontalCenter : undefined
        anchors.left: root.align === "left" ? parent.left : undefined
        anchors.right: root.align === "right" ? parent.right : undefined
        // qmllint enable Quick.anchor-combinations
        anchors.top: root.below ? parent.top : undefined
        anchors.bottom: root.below ? undefined : parent.bottom
        onVisibleChanged: if (visible) requestPaint()
        Connections {
            target: Theme
            function onCreamChanged() { pointer.requestPaint(); }
        }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = Theme.cream;
            ctx.beginPath();
            if (root.below) {
                ctx.moveTo(0, height);
                ctx.lineTo(width, height);
                ctx.lineTo(width / 2, 0);
            } else {
                ctx.moveTo(0, 0);
                ctx.lineTo(width, 0);
                ctx.lineTo(width / 2, height);
            }
            ctx.closePath();
            ctx.fill();
        }
    }
}
