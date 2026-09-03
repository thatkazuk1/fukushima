pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../../components"

/**
 * Game-mode bar face: a compact top strip shown while Flags.gameMode is on.
 * Left: now-playing (art + title/artist). Centre: the clock. Right: a
 * volume/brightness/mic feedback chip (the full OSD is parked behind game mode
 * in the mode ladder) and the exit-game-mode button.
 *
 * Pure view. The host sets anchors and feeds `mode` / `morphCloseness` / `s`
 * from the pill, `clockText` from its clock, and `osd` (the Osd flash
 * controller) for the live level chip.
 */
Item {
    id: gameBar

    property real s: 1
    property string mode: ""
    property real morphCloseness: 1
    property string clockText: ""
    property var osd: null

    enabled: gameBar.mode === "game"
    opacity: gameBar.mode === "game" ? Math.pow(gameBar.morphCloseness, 1.2) : 0
    visible: opacity > 0.01

    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 18 * gameBar.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9 * gameBar.s
            opacity: Players.has ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 26 * gameBar.s
                height: 26 * gameBar.s
                radius: 7 * gameBar.s
                color: Theme.tileBg
                clip: true
                Image {
                    anchors.fill: parent
                    source: Players.artUrl
                    sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: Players.title
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12.5 * gameBar.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 220 * gameBar.s)
                }
                Text {
                    text: Players.artist
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * gameBar.s
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 220 * gameBar.s)
                    visible: text.length > 0
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: gameBar.clockText
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 16 * gameBar.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }

        /**
         * Volume/brightness/mic feedback stays visible while gaming as a compact
         * chip on the bar's right, since the full OSD face is parked behind
         * game mode in the mode ladder. Notifications stay suppressed.
         */
        Rectangle {
            id: exitChip
            anchors.right: parent.right
            anchors.rightMargin: 14 * gameBar.s
            anchors.verticalCenter: parent.verticalCenter
            width: 26 * gameBar.s
            height: 26 * gameBar.s
            radius: 8 * gameBar.s
            color: exitHover.hovered ? Theme.frameBg : Qt.alpha(Theme.tileBg, 0.45)
            border.width: 1
            border.color: exitHover.hovered ? Qt.alpha(Theme.onGlow, 0.5) : Theme.border
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            GlyphIcon {
                anchors.centerIn: parent
                width: 15 * gameBar.s
                height: 15 * gameBar.s
                name: "gamepad"
                color: exitHover.hovered ? Theme.vermLit : Theme.iconDim
                stroke: 1.7
            }
            HoverHandler {
                id: exitHover
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Flags.gameMode = false
            }
            Tooltip {
                s: gameBar.s
                placement: "below"
                align: "right"
                title: "Exit game mode"
                desc: "Restore the desktop"
                show: exitHover.hovered
            }
        }

        Row {
            anchors.right: exitChip.left
            anchors.rightMargin: 9 * gameBar.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9 * gameBar.s
            opacity: gameBar.osd.flashing && (gameBar.osd.kind === "volume" || gameBar.osd.kind === "brightness" || gameBar.osd.kind === "mic") ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 14 * gameBar.s
                height: 14 * gameBar.s
                name: gameBar.osd.kind === "brightness" ? "sun"
                    : (gameBar.osd.kind === "mic" ? (gameBar.osd.micMuted ? "mic-off" : "mic")
                    : (gameBar.osd.muted ? "speaker-off" : "speaker"))
                color: (gameBar.osd.kind === "volume" && gameBar.osd.muted) || (gameBar.osd.kind === "mic" && gameBar.osd.micMuted) ? Theme.dim : Theme.iconDim
                stroke: 1.7
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 64 * gameBar.s
                height: 3 * gameBar.s
                radius: 1.5 * gameBar.s
                color: Theme.threadBg

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (gameBar.osd.kind === "brightness" ? gameBar.osd.brightness
                        : (gameBar.osd.kind === "mic" ? gameBar.osd.micVolume : gameBar.osd.volume))
                    radius: parent.radius
                    color: (gameBar.osd.kind === "volume" && gameBar.osd.muted) || (gameBar.osd.kind === "mic" && gameBar.osd.micMuted) ? Theme.vermDim : Theme.vermLit
                    Behavior on width { NumberAnimation { duration: Motion.fast } }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: gameBar.osd.kind === "mic"
                    ? (gameBar.osd.micMuted ? "off" : Math.round(gameBar.osd.micVolume * 100) + "%")
                    : Math.round((gameBar.osd.kind === "brightness" ? gameBar.osd.brightness : gameBar.osd.volume) * 100) + "%"
                color: (gameBar.osd.kind === "volume" && gameBar.osd.muted) || (gameBar.osd.kind === "mic" && gameBar.osd.micMuted) ? Theme.dim : Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * gameBar.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
}
