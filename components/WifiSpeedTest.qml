pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../config"

/**
 * Inline internet speed test for the wifi surface (relocated from the system
 * monitor). scripts/net-speedtest.sh streams `ping` / `down` / `up` lines as
 * each time-boxed phase against speed.cloudflare.com finishes; a curl
 * `--max-time` cutoff is the normal end of a phase, not a failure. Covers the
 * panel while `open`; `requestClose` dismisses.
 */
Item {
    id: root

    property real s: 1
    property bool open: false
    signal requestClose()

    property bool running: false
    property string phase: ""
    property real ping: 0
    property real down: 0
    property real up: 0
    property bool done: false
    property string error: ""

    function fmt(mbps) {
        return mbps >= 1000 ? (mbps / 1000).toFixed(1) + " Gbps" : mbps.toFixed(1) + " Mbps";
    }

    function start() {
        if (root.running)
            return;
        root.running = true;
        root.done = false;
        root.error = "";
        root.phase = "ping";
        root.ping = 0;
        root.down = 0;
        root.up = 0;
        proc.running = true;
    }

    function stop() {
        root.running = false;
        root.phase = "";
        proc.running = false;
    }

    onOpenChanged: if (!open) stop()

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
        width: parent.width - 40 * root.s
        spacing: 12 * root.s

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "SPEED TEST"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.8 * root.s
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 26 * root.s
            visible: root.running || root.done

            Repeater {
                model: [
                    { k: "Ping", v: root.ping > 0 ? Math.round(root.ping) + " ms" : "—", live: root.phase === "ping" },
                    { k: "Down", v: root.down > 0 ? root.fmt(root.down) : "—", live: root.phase === "download" },
                    { k: "Up", v: root.up > 0 ? root.fmt(root.up) : "—", live: root.phase === "upload" }
                ]
                delegate: Column {
                    id: cell
                    required property var modelData
                    spacing: 3 * root.s
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.v
                        color: cell.modelData.live ? Theme.flameGlow : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 15 * root.s
                        font.weight: Font.DemiBold
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.modelData.k
                        color: Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1 * root.s
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.error.length > 0
            text: root.error
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: runLabel.implicitWidth + 26 * root.s
            height: 26 * root.s
            radius: 8 * root.s
            visible: !root.running
            color: runArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.16) : Theme.tileBg
            border.width: 1
            border.color: runArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.5) : Theme.border
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                id: runLabel
                anchors.centerIn: parent
                text: root.done || root.error.length ? "Run again" : "Start test"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 10.5 * root.s
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: runArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.start()
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 7 * root.s
            visible: root.running

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 5 * root.s
                height: 5 * root.s
                radius: width / 2
                color: Theme.flameGlow
                SequentialAnimation on opacity {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phase === "ping" ? "Measuring latency…"
                    : (root.phase === "download" ? "Testing download…"
                    : (root.phase === "upload" ? "Testing upload…" : "Working…"))
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
            }
        }
    }

    Process {
        id: proc
        command: ["bash", Config.hyprPath("scripts", "net-speedtest.sh")]
        stdout: SplitParser {
            onRead: (line) => {
                var tab = line.indexOf("\t");
                if (tab < 1)
                    return;
                var k = line.slice(0, tab);
                var v = line.slice(tab + 1).trim();
                if (k === "ping") {
                    root.ping = parseFloat(v) || 0;
                    root.phase = "download";
                } else if (k === "down") {
                    root.down = parseFloat(v) || 0;
                    root.phase = "upload";
                } else if (k === "up") {
                    root.up = parseFloat(v) || 0;
                    root.phase = "done";
                } else if (k === "fail") {
                    root.error = v === "ping" ? "No internet connection"
                        : "Connection lost during " + v;
                    root.running = false;
                    proc.running = false;
                }
            }
        }
        onExited: {
            root.running = false;
            root.phase = root.error.length ? "" : "done";
            if (!root.error.length && root.up > 0)
                root.done = true;
        }
    }
}
