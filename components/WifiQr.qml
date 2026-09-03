pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../config"

/**
 * Wi-Fi share card: the active network encoded as a QR the phone camera joins
 * from. scripts/net-qr.sh emits a meta line then a 0/1 matrix (quiet zone
 * included); this draws it as native rectangles on a light tile so a scanner
 * gets the contrast it needs. Covers the panel while `open`.
 */
Item {
    id: root

    property real s: 1
    property bool open: false
    signal requestClose()

    property var matrix: []
    property string ssid: ""
    property string security: ""
    property string error: ""

    readonly property int dim: matrix.length

    onOpenChanged: {
        if (open) {
            root.matrix = [];
            root.error = "";
            proc.running = true;
        }
    }

    enabled: open
    opacity: open ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }

    Rectangle {
        anchors.fill: parent
        color: Theme.cardBot
    }

    MouseArea { anchors.fill: parent }

    GlyphIcon {
        anchors.top: parent.top
        anchors.right: parent.right
        width: 13 * root.s
        height: 13 * root.s
        name: "chevron-left"
        color: backArea.containsMouse ? Theme.cream : Theme.faint
        stroke: 2
        MouseArea {
            id: backArea
            anchors.fill: parent
            anchors.margins: -7 * root.s
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.requestClose()
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 10 * root.s

        Rectangle {
            id: tile
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real px: root.dim > 0 ? Math.floor((150 * root.s) / root.dim) : 4
            width: root.dim > 0 ? root.dim * px : 150 * root.s
            height: width
            radius: 8 * root.s
            color: root.error.length ? Theme.cardBot : "#f4f1ea"
            visible: root.error.length === 0

            Column {
                anchors.centerIn: parent
                Repeater {
                    model: root.matrix
                    delegate: Row {
                        id: qrRow
                        required property var modelData
                        Repeater {
                            model: qrRow.modelData.length
                            delegate: Rectangle {
                                id: qrCell
                                required property int index
                                width: tile.px
                                height: tile.px
                                color: qrRow.modelData[qrCell.index] === "1" ? "#141210" : "transparent"
                            }
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.error.length === 0 && root.ssid.length > 0
            text: root.ssid
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.error.length === 0
            text: root.security === "nopass" ? "Open network" : "Scan to join"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1 * root.s
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.error.length > 0
            width: 200 * root.s
            horizontalAlignment: Text.AlignHCenter
            text: root.error
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            wrapMode: Text.WordWrap
        }
    }

    Process {
        id: proc
        command: ["bash", Config.hyprPath("scripts", "net-qr.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = [];
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("meta\t") === 0) {
                        var m = lines[i].split("\t");
                        root.ssid = m[1] || "";
                        root.security = m[2] || "";
                    } else if (/^[01]+$/.test(lines[i])) {
                        rows.push(lines[i]);
                    }
                }
                root.matrix = rows;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (t.length)
                    root.error = t.charAt(0).toUpperCase() + t.slice(1);
            }
        }
    }
}
