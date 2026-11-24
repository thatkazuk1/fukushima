import QtQuick
import QtQuick.Shapes
import "../config"

/**
 * Radial gauge. One ring shows `outerPct`; when `innerPct` is also set a second,
 * smaller ring sits inside it (the usage flyout puts the weekly window on the
 * outer ring and the 5 hour session on the inner one). Values run 0 to 100, and
 * -1 means "no ring". The arc animates when a value changes. Colour follows the
 * load: `idleColor` below 80, flame from 80, vermilion from 95. With `dim` set
 * the rings stay as faint empty tracks, which is how a provider without data
 * looks. Children go into `center`, which is the middle of the rings.
 */
Item {
    id: root

    property real s: 1
    /** Diameter before the `s` scale. */
    property real size: 64
    /** Ring thickness before the `s` scale. */
    property real stroke: 5
    property real outerPct: -1
    property real innerPct: -1
    property bool dim: false
    property color idleColor: Theme.iconDim

    default property alias content: center.data
    readonly property alias center: center

    readonly property real dia: size * s
    readonly property real sw: stroke * s
    readonly property real gap: Math.max(2, stroke * 0.55) * s
    readonly property real r1: dia / 2 - sw / 2
    readonly property real r2: r1 - sw - gap
    readonly property bool twin: innerPct >= 0

    function tint(p) {
        return p >= 95 ? Theme.vermLit : (p >= 80 ? Theme.flameGlow : root.idleColor);
    }

    /** Animated copies of the inputs; the arcs read these. */
    property real aOuter: Math.max(0, outerPct)
    property real aInner: Math.max(0, innerPct)
    Behavior on aOuter { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard } }
    Behavior on aInner { NumberAnimation { duration: Motion.morph; easing.type: Motion.easeStandard } }

    implicitWidth: dia
    implicitHeight: dia
    width: dia
    height: dia

    function sweep(p) { return Math.min(359.9, Math.max(0, p) * 3.6); }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.dim ? 0.5 : 1

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.threadBg
            strokeWidth: root.sw
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.dia / 2; centerY: root.dia / 2
                radiusX: root.r1; radiusY: root.r1
                startAngle: -90; sweepAngle: 359.9
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: (root.outerPct >= 0 && !root.dim && root.aOuter > 0.2)
                ? root.tint(root.outerPct) : "transparent"
            strokeWidth: root.sw
            capStyle: ShapePath.RoundCap
            Behavior on strokeColor { ColorAnimation { duration: Motion.standard } }
            PathAngleArc {
                centerX: root.dia / 2; centerY: root.dia / 2
                radiusX: root.r1; radiusY: root.r1
                startAngle: -90; sweepAngle: root.sweep(root.aOuter)
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.twin ? Theme.threadBg : "transparent"
            strokeWidth: root.sw
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.dia / 2; centerY: root.dia / 2
                radiusX: root.r2; radiusY: root.r2
                startAngle: -90; sweepAngle: 359.9
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: (root.twin && !root.dim && root.aInner > 0.2)
                ? root.tint(root.innerPct) : "transparent"
            strokeWidth: root.sw
            capStyle: ShapePath.RoundCap
            Behavior on strokeColor { ColorAnimation { duration: Motion.standard } }
            PathAngleArc {
                centerX: root.dia / 2; centerY: root.dia / 2
                radiusX: root.r2; radiusY: root.r2
                startAngle: -90; sweepAngle: root.sweep(root.aInner)
            }
        }
    }

    Item {
        id: center
        anchors.centerIn: parent
        width: Math.max(0, (root.twin ? root.r2 - root.sw / 2 : root.r1 - root.sw / 2) * 2 * 0.92)
        height: width
    }
}
