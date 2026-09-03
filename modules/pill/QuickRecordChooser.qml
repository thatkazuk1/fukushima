pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../../components"

/**
 * Standalone quick-record source chooser (SUPER+D with no recorder surface
 * open). Grows the pill on the focused monitor only and offers the same Screen
 * and Window / Region picks as the recorder surface; one monitor resolves at
 * once, several flip to an inline sub-choice. A pick fires
 * ScreenRec.prepareScreen / prepareWindow, then the central countdown Item
 * takes over (mode "quickCount") and cancels on a tap.
 *
 * Pure driver over the ScreenRec singleton. Host feeds s / mode /
 * morphCloseness / screenName.
 */
Item {
    id: root

    property real s: 1
    property string mode: ""
    property real morphCloseness: 1
    property string screenName: ""

    function chooseSource(kind) {
        if (kind === "screen") {
            if (ScreenRec.monitors.length > 1) {
                ScreenRec.quickScreenChoosing = true;
                return;
            }
            ScreenRec.prepareScreen(root.screenName);
        } else if (kind === "window") {
            ScreenRec.prepareWindow();
        }
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
    }

    function pickMonitor(name) {
        ScreenRec.quickChoosing = false;
        ScreenRec.quickScreenChoosing = false;
        ScreenRec.prepareScreen(name);
    }

    Item {
        id: quickChooser
        anchors.fill: parent
        anchors.margins: 6 * root.s
        enabled: root.mode === "quickChoose"
        opacity: root.mode === "quickChoose" ? Math.pow(root.morphCloseness, 1.3) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Row {
            id: quickSources
            anchors.fill: parent
            visible: !ScreenRec.quickScreenChoosing
            spacing: 6 * root.s

            Repeater {
                model: [
                    { kind: "screen", label: "Screen", glyph: "monitor" },
                    { kind: "window", label: "Window / Region", glyph: "video" }
                ]

                Rectangle {
                    id: qSrcTile
                    required property var modelData
                    width: (quickSources.width - 6 * root.s) / 2
                    height: parent.height
                    radius: 11 * root.s
                    color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                    border.width: 1
                    border.color: qSrcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8 * root.s

                        GlyphIcon {
                            width: 16 * root.s
                            height: 16 * root.s
                            name: qSrcTile.modelData.glyph
                            color: qSrcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                            stroke: 1.7
                        }
                        Text {
                            height: 16 * root.s
                            verticalAlignment: Text.AlignVCenter
                            text: qSrcTile.modelData.label
                            color: qSrcArea.containsMouse ? Theme.cream : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: qSrcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chooseSource(qSrcTile.modelData.kind)
                    }
                }
            }
        }

        ListView {
            id: quickScreens
            anchors.fill: parent
            anchors.rightMargin: 22 * root.s
            visible: ScreenRec.quickScreenChoosing
            orientation: ListView.Horizontal
            spacing: 6 * root.s
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ScreenRec.monitors

            delegate: Rectangle {
                id: qMonTile
                required property var modelData
                width: 152 * root.s
                height: quickScreens.height
                radius: 11 * root.s
                color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
                border.width: 1
                border.color: qMonArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
                Behavior on color { ColorAnimation { duration: Motion.fast } }

                Column {
                    anchors.centerIn: parent
                    spacing: 2 * root.s

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qMonTile.modelData.name
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 11.5 * root.s
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qMonTile.modelData.w + " × " + qMonTile.modelData.h
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                        font.features: { "tnum": 1 }
                    }
                }

                MouseArea {
                    id: qMonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickMonitor(qMonTile.modelData.name)
                }
            }
        }

        WheelScroller {
            flick: quickScreens
            s: root.s
            anchors.fill: quickScreens
            visible: ScreenRec.quickScreenChoosing
        }

        GlyphIcon {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 5 * root.s
            visible: ScreenRec.quickScreenChoosing
            width: 12 * root.s
            height: 12 * root.s
            name: "chevron-left"
            color: qBackArea.containsMouse ? Theme.cream : Theme.faint
            stroke: 2

            MouseArea {
                id: qBackArea
                anchors.fill: parent
                anchors.margins: -7 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ScreenRec.quickScreenChoosing = false
            }
        }
    }

    /**
     * Standalone pre-roll countdown toast. Shown at the pill top on the focused
     * monitor when the central countdown runs and the recorder surface is closed
     * (mode "quickCount"): a big flame-glow numeral over a small "GET READY" label.
     * Tapping cancels. The surface's own in-bar countdown covers the surface case.
     */
    Item {
        id: quickCount
        anchors.fill: parent
        enabled: root.mode === "quickCount"
        opacity: root.mode === "quickCount" ? Math.pow(root.morphCloseness, 1.3) : 0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard }
        }

        Column {
            anchors.centerIn: parent
            spacing: 1 * root.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ScreenRec.countdown
                color: Theme.flameGlow
                font.family: Theme.font
                font.pixelSize: 28 * root.s
                font.weight: Font.ExtraBold
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "GET READY"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ScreenRec.cancel()
        }
    }
}
