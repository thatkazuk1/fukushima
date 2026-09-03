pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../config"
import "../../services"
import "../../components"

/**
 * File drag-and-drop installer. A file dragged onto the resting pill routes
 * through scripts/app-install.sh by type (AppImages/packages install, fonts
 * land in the font dir, images become the wallpaper). The drop face frames a
 * stage glyph + label that walks drop -> spinner -> checkmark; a bad type
 * flashes a rejection.
 *
 * Self-contained: owns all drag/install state and exposes only `active` (the
 * pill folds this into its `mode` ladder as "dragOver") and a `requestSurface`
 * signal. Host feeds `s`, `morphCloseness`, `surfaceOpen`.
 */
Item {
    id: dragInstall

    property real s: 1
    property real morphCloseness: 1
    property bool surfaceOpen: false
    signal requestSurface(string name)

    readonly property bool active: dragInstall.dragActive

    /**
     * AppImage drag-install state, live only while a file hovers the resting pill.
     * `dragStage` walks hover -> installing -> done, or bad for a non-AppImage drop.
     */
    property bool dragActive: false
    property string dragName: ""
    property string dragStage: ""

    property var installQueue: []

    function localPath(url) {
        var s = String(url);
        if (s.indexOf("file://") === 0)
            s = s.substring(7);
        return decodeURIComponent(s);
    }

    readonly property var dropExt: /\.(appimage|deb|rpm|flatpakref|zip|tgz|txz|tbz2|ttf|otf|png|jpe?g|webp)$|\.(pkg\.)?tar\.(gz|xz|bz2|zst)$/i

    function droppablePaths(urls) {
        var out = [];
        for (var i = 0; i < urls.length; i++)
            if (dragInstall.dropExt.test(String(urls[i])))
                out.push(dragInstall.localPath(urls[i]));
        return out;
    }

    function dropLabel(urls) {
        var p = dragInstall.localPath(urls.length ? urls[0] : "");
        return p.substring(p.lastIndexOf("/") + 1).replace(dragInstall.dropExt, "");
    }

    property bool installedAny: false
    property bool installedApp: false
    property bool installFailed: false
    property string installKind: "app"
    property string installAction: "new"
    property string installLine: ""
    property string installProto: ""
    property string installPct: ""
    property int installSeconds: 0

    function runNextInstall() {
        if (dragInstall.installQueue.length === 0) {
            dragInstall.dragStage = dragInstall.installedAny ? "done" : "fail";
            (dragInstall.installedAny ? dropDoneTimer : dropBadTimer).restart();
            return;
        }
        var next = dragInstall.installQueue.shift();
        dragInstall.dragName = next.substring(next.lastIndexOf("/") + 1).replace(dragInstall.dropExt, "");
        dragInstall.installLine = "";
        dragInstall.installProto = "";
        dragInstall.installPct = "";
        installProc.command = ["bash", Config.hyprPath("scripts", "app-install.sh"), "install", next];
        installProc.running = true;
    }

    /**
     * Streams installer stdout instead of collecting it: slow backends (flatpak
     * runtime pulls, pacman) narrate their steps, and the drop face mirrors the
     * newest line live. The machine-readable result is the one tab-separated
     * kind-prefixed line, fished out of the stream as it passes.
     */
    Process {
        id: installProc
        stdout: SplitParser {
            onRead: (data) => {
                var seg = data.split("\r").pop().replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
                if (seg.length === 0)
                    return;
                if (/^(app|native|font|wallpaper)\t/.test(seg)) {
                    dragInstall.installProto = seg;
                } else {
                    dragInstall.installLine = seg;
                    var pct = seg.match(/(\d{1,3})\s*%/);
                    if (pct && Number(pct[1]) <= 100)
                        dragInstall.installPct = pct[1] + "%";
                }
            }
        }
        onExited: (exitCode) => {
            if (exitCode === 0 && dragInstall.installProto.length > 0) {
                dragInstall.installedAny = true;
                var parts = dragInstall.installProto.split("\t");
                dragInstall.installKind = parts[0];
                dragInstall.installAction = parts[2];
                if (parts[0] === "app" || parts[0] === "native")
                    dragInstall.installedApp = true;
                if (parts[0] === "font" && parts.length >= 4)
                    droppedFont.source = "file://" + parts[3];
            } else {
                dragInstall.installFailed = true;
            }
            dragInstall.runNextInstall();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: dragInstall.dragStage === "installing"
        onTriggered: dragInstall.installSeconds++
    }

    /**
     * Registers a just-dropped font in this running process; the fontconfig
     * cache alone only reaches apps started later. Ready -> the font picker's
     * family list refreshes and the new face shows up without a restart.
     */
    FontLoader {
        id: droppedFont
        onStatusChanged: if (status === FontLoader.Ready) Theme.refreshFonts()
    }

    Timer {
        id: dropDoneTimer
        interval: 1100
        onTriggered: {
            dragInstall.dragActive = false;
            dragInstall.dragStage = "";
            if (dragInstall.installedApp)
                dragInstall.requestSurface("launcher");
        }
    }

    Timer {
        id: dropBadTimer
        interval: 1300
        onTriggered: {
            dragInstall.dragActive = false;
            dragInstall.dragStage = "";
        }
    }

    /**
     * File drops land only on the resting pill; an open surface turns the pill
     * into a fullscreen modal that swallows the drag before it can start.
     * app-install.sh routes each drop by type (apps install, fonts land in the
     * font dir, images become the wallpaper), anything else flashes a rejection.
     */
    DropArea {
        anchors.fill: parent
        enabled: !dragInstall.surfaceOpen && dragInstall.dragStage !== "installing" && dragInstall.dragStage !== "done"
        keys: ["text/uri-list"]
        onEntered: (drag) => {
            drag.acceptProposedAction();
            dragInstall.dragActive = true;
            dragInstall.dragStage = dragInstall.droppablePaths(drag.urls).length > 0 ? "hover" : "bad";
            dragInstall.dragName = dragInstall.dropLabel(drag.urls);
        }
        onExited: {
            if (dragInstall.dragStage === "hover" || dragInstall.dragStage === "bad") {
                dragInstall.dragActive = false;
                dragInstall.dragStage = "";
            }
        }
        onDropped: (drop) => {
            drop.acceptProposedAction();
            var files = dragInstall.droppablePaths(drop.urls);
            if (files.length === 0) {
                dragInstall.dragActive = true;
                dragInstall.dragStage = "bad";
                dragInstall.dragName = dragInstall.dropLabel(drop.urls);
                dropBadTimer.restart();
                return;
            }
            dragInstall.dragActive = true;
            dragInstall.dragStage = "installing";
            dragInstall.installedAny = false;
            dragInstall.installedApp = false;
            dragInstall.installFailed = false;
            dragInstall.installKind = "app";
            dragInstall.installAction = "new";
            dragInstall.installSeconds = 0;
            dragInstall.installQueue = files;
            dragInstall.runNextInstall();
        }
    }

    /**
     * Drop-zone face: corner brackets frame a stage glyph and label that walk
     * from "drop to install" through the spinner to a checkmark. Shares the morph
     * fade of the other pill faces, so it grows in as the pill reaches its size.
     */
    Item {
        id: dragOverView
        anchors.fill: parent
        anchors.margins: 11 * dragInstall.s
        enabled: dragInstall.dragActive
        opacity: dragInstall.dragActive ? Math.pow(dragInstall.morphCloseness, 1.2) : 0
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

        readonly property color accent: (dragInstall.dragStage === "bad" || dragInstall.dragStage === "fail") ? "#e0533f" : Theme.vermLit
        readonly property real brLen: 15 * dragInstall.s
        readonly property real brThick: 2 * dragInstall.s

        Repeater {
            model: [[0, 0], [1, 0], [0, 1], [1, 1]]
            delegate: Item {
                id: corner
                required property var modelData
                readonly property bool rightSide: modelData[0] === 1
                readonly property bool bottomSide: modelData[1] === 1
                x: rightSide ? dragOverView.width - dragOverView.brLen : 0
                y: bottomSide ? dragOverView.height - dragOverView.brLen : 0
                width: dragOverView.brLen
                height: dragOverView.brLen

                Rectangle {
                    width: dragOverView.brLen
                    height: dragOverView.brThick
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
                Rectangle {
                    width: dragOverView.brThick
                    height: dragOverView.brLen
                    radius: dragOverView.brThick / 2
                    color: dragOverView.accent
                    anchors.top: corner.bottomSide ? undefined : parent.top
                    anchors.bottom: corner.bottomSide ? parent.bottom : undefined
                    anchors.left: corner.rightSide ? undefined : parent.left
                    anchors.right: corner.rightSide ? parent.right : undefined
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 44 * dragInstall.s
            spacing: 7 * dragInstall.s

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 26 * dragInstall.s
                height: 26 * dragInstall.s

                GlyphIcon {
                    id: dragGlyph
                    anchors.fill: parent
                    stroke: 2
                    color: dragOverView.accent
                    name: (dragInstall.dragStage === "bad" || dragInstall.dragStage === "fail") ? "close"
                        : (dragInstall.dragStage === "installing" ? "reboot"
                        : (dragInstall.dragStage === "done" ? "check" : "download"))

                    RotationAnimation on rotation {
                        running: dragInstall.dragStage === "installing"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                    onNameChanged: if (dragInstall.dragStage !== "installing") rotation = 0
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dragInstall.dragStage === "bad" ? "Can't install this"
                    : (dragInstall.dragStage === "fail" ? "Install failed"
                    : (dragInstall.dragStage === "installing" ? ("Installing"
                        + (dragInstall.installPct.length > 0 ? " " + dragInstall.installPct : "")
                        + (dragInstall.installSeconds >= 3 ? "  " + Math.floor(dragInstall.installSeconds / 60) + ":" + String(dragInstall.installSeconds % 60).padStart(2, "0") : ""))
                    : (dragInstall.dragStage === "done" ? (dragInstall.installFailed ? "Installed, some failed"
                        : (!dragInstall.installedApp && dragInstall.installKind === "wallpaper" ? "Wallpaper set"
                        : (!dragInstall.installedApp && dragInstall.installKind === "font" ? "Font installed"
                        : (dragInstall.installAction === "updated" ? "Updated"
                        : (dragInstall.installAction === "reinstalled" ? "Reinstalled" : "Installed")))))
                    : "Drop to install")))
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * dragInstall.s
                font.weight: Font.Medium
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: dragInstall.dragStage === "installing" && dragInstall.installLine.length > 0 ? dragInstall.installLine : dragInstall.dragName
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * dragInstall.s
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }
}
