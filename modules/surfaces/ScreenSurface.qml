pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../config"
import "../../services"
import "../../components"

/**
 * 画 DISPLAY surface: the screen counterpart to the audio Mixer. Brightness for
 * the focused output (ddcutil for external panels, brightnessctl for the built-in
 * one), screen vibrance (nvibrant), a live monitor-scale preset pushed straight
 * to Hyprland, the night-light toggle and the keep-awake lock, and a list of
 * every connected output that switches focus on tap. Opened from the monitor
 * icon in the pill's hover row; re-probes the hardware each time it opens.
 *
 * Built on SettingsSurface so the row seam, hover tracking and keyboard nav
 * (arrows adjust, Return activates) come for free — the two faders register as
 * `scrub` rows and step 5% per notch, mirroring the Mixer's fader contract.
 */
SettingsSurface {
    id: root

    backSurface: ""
    implicitHeight: content.implicitHeight

    // The loader wakes on first open, so this probes the hardware then; a later
    // hot-plug is picked up by re-opening after a shell reload (as the Mixer did).
    Component.onCompleted: {
        Devices.detect();
        scaleQuery.running = true;
    }

    // Re-probe whenever the surface is re-opened, without shadowing the base
    // SettingsSurface.onActiveChanged (a derived on<Signal> handler would).
    Connections {
        target: root
        function onActiveChanged() {
            if (root.active) {
                Devices.detect();
                scaleQuery.running = true;
            }
        }
    }

    // --- brightness target resolution ------------------------------------

    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    /** ddcutil bus for the focused monitor, or "" when it is not a DDC panel. */
    readonly property string focusedDdcBus: {
        var m = Devices.ddcMonitors;
        for (var i = 0; i < m.length; i++)
            if (m[i].label === root.focusedName)
                return m[i].bus;
        return "";
    }
    readonly property bool focusedIsInternal: focusedDdcBus === "" && Devices.backlightPresent
    readonly property bool brightnessAvailable: focusedDdcBus !== "" || focusedIsInternal

    /** Last brightness read off the focused DDC panel (internal uses Devices.backlightPct). */
    property int ddcPct: 75
    property real pendingBacklight: -1
    property int pendingDdc: -1

    onFocusedDdcBusChanged: if (focusedDdcBus !== "") ddcRead.running = true

    Timer {
        id: blDebounce
        interval: 160
        onTriggered: if (root.pendingBacklight >= 0) {
            Devices.setBacklight(root.pendingBacklight);
            root.pendingBacklight = -1;
        }
    }

    Timer {
        id: ddcDebounce
        interval: 160
        onTriggered: if (root.pendingDdc >= 0) {
            Devices.setBrightness(root.focusedDdcBus, root.pendingDdc);
            root.pendingDdc = -1;
        }
    }

    Process {
        id: ddcRead
        command: ["timeout", "3", "ddcutil", "getvcp", "10", "--bus", root.focusedDdcBus, "--brief"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = Devices.parseBrightness(this.text);
                if (v >= 0)
                    root.ddcPct = v;
            }
        }
    }

    /**
     * Keep the built-in backlight value live when swayosd or the brightness keys
     * write the sysfs node behind our back (mirrors the Mixer's old wiring).
     */
    Connections {
        target: Backlight
        function onChanged() {
            Devices.backlightPct = Math.round(Backlight.brightness * 100);
        }
    }

    // --- vibrance -------------------------------------------------------

    property real pendingVibrance: -1
    Timer {
        id: vibDebounce
        interval: 160
        onTriggered: if (root.pendingVibrance >= 0) {
            Devices.setVibrance(root.pendingVibrance);
            root.pendingVibrance = -1;
        }
    }

    // --- scale ---------------------------------------------------------

    /**
     * Live scale of the focused output. Quickshell's Hyprland monitor model is
     * not refreshed by a `keyword monitor` change, so the seg would snap back to
     * a stale value — this is read straight from `hyprctl monitors -j` instead,
     * on open, on focus change, and after we push a new scale.
     */
    property real liveScale: 0

    readonly property real focusedScale: {
        if (root.liveScale > 0)
            return root.liveScale;
        var m = Hyprland.focusedMonitor;
        return m && m.scale ? m.scale : 1;
    }

    onFocusedNameChanged: scaleQuery.running = true

    Process {
        id: scaleQuery
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var mons = JSON.parse(this.text);
                    for (var i = 0; i < mons.length; i++) {
                        if (mons[i].focused) {
                            root.liveScale = mons[i].scale;
                            return;
                        }
                    }
                } catch (e) {
                }
            }
        }
    }

    /**
     * Hyprland fires no event for a `keyword monitor` scale change, so while the
     * surface is open the applied scale is re-read on a slow poll — this also
     * reconciles the optimistic value set in applyScale() with whatever factor
     * Hyprland actually settled on (it nudges to a pixel-divisible one).
     */
    Timer {
        running: root.active
        interval: 1500
        repeat: true
        onTriggered: scaleQuery.running = true
    }

    readonly property var scalePresets: [1, 1.25, 1.5, 1.75, 2]

    /** Nearest preset to the live scale, so the segment reflects reality. */
    readonly property real scaleChoice: {
        var opts = root.scalePresets;
        var best = opts[0];
        var bd = 99;
        for (var i = 0; i < opts.length; i++) {
            var d = Math.abs(opts[i] - root.focusedScale);
            if (d < bd) {
                bd = d;
                best = opts[i];
            }
        }
        return best;
    }

    function applyScale(v) {
        if (root.focusedName === "")
            return;
        Quickshell.execDetached(["hyprctl", "keyword", "monitor",
            root.focusedName + ",preferred,auto," + String(v)]);
        // Reflect the pick straight away; the poll reconciles it with the factor
        // Hyprland actually settled on a moment later.
        root.liveScale = v;
    }

    // --- keyboard row registry --------------------------------------------

    rows: {
        var r = [];
        if (root.brightnessAvailable)
            r.push({ item: briRow, kind: "scrub", bump: function (d) { briRow.step(d * 5); } });
        r.push({ item: vibRow, kind: "scrub", bump: function (d) { vibRow.step(d * 5); } });
        r.push({ item: scaleRow, kind: "seg", vals: root.scalePresets,
            get: function () { return root.scaleChoice; },
            set: function (v) { root.applyScale(v); } });
        r.push({ item: nlRow, kind: "toggle",
            get: function () { return Flags.nightLightMode !== "off"; },
            set: function (v) { NightLight.setMode(v ? "on" : "off"); } });
        r.push({ item: awakeRow, kind: "toggle",
            get: function () { return Flags.keepAwake; },
            set: function (v) { Flags.keepAwake = v; } });
        return r;
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "画"
            title: "DISPLAY"
            showBack: false
        }

        Item { width: 1; height: 10 * root.s }

        SectionLabel {
            s: root.s
            text: "Brightness"
            visible: root.brightnessAvailable
        }

        FaderRow {
            id: briRow
            surface: root
            labelWidth: 62 * root.s
            visible: root.brightnessAvailable
            icon: "sun"
            label: root.focusedName.length > 0 ? root.focusedName : "Screen"
            value: root.focusedDdcBus !== "" ? root.ddcPct / 100 : Devices.backlightPct / 100
            onMoved: (v) => {
                if (root.focusedDdcBus !== "")
                    root.ddcPct = Math.max(5, Math.min(100, Math.round(v * 100)));
                else
                    Devices.backlightPct = Math.max(1, Math.min(100, Math.round(v * 100)));
            }
            onCommitted: (v) => {
                if (root.focusedDdcBus !== "") {
                    root.pendingDdc = Math.max(5, Math.min(100, Math.round(v * 100)));
                    ddcDebounce.restart();
                } else {
                    root.pendingBacklight = Math.max(1, Math.min(100, Math.round(v * 100)));
                    blDebounce.restart();
                }
            }
        }

        SectionLabel { s: root.s; text: "Colour" }

        FaderRow {
            id: vibRow
            surface: root
            labelWidth: 62 * root.s
            icon: "palette"
            label: "Vibrance"
            value: Devices.vibrance / 100
            onMoved: (v) => Devices.vibrance = Math.round(v * 100)
            onCommitted: (v) => {
                root.pendingVibrance = v * 100;
                vibDebounce.restart();
            }
        }

        SectionLabel { s: root.s; text: "Scale" }

        SettingsRow {
            id: scaleRow
            surface: root
            name: "Resolution scale"
            sub: root.focusedScale > 0 ? "now " + (Math.round(root.focusedScale * 100) / 100) + "×" : ""
            icon: "scaling"

            SettingsSeg {
                s: root.s
                options: root.scalePresets.map(v => ({ label: v + "×", value: v }))
                value: root.scaleChoice
                onPicked: (v) => root.applyScale(v)
            }
        }

        SectionLabel { s: root.s; text: "Screen" }

        SettingsRow {
            id: nlRow
            surface: root
            name: "Night light"
            icon: "moon"

            LinkToggle {
                s: root.s
                on: Flags.nightLightMode !== "off"
                onToggled: NightLight.setMode(Flags.nightLightMode === "off" ? "on" : "off")
            }
        }

        SettingsRow {
            id: awakeRow
            surface: root
            name: "Keep awake"
            icon: "awake"
            last: true

            LinkToggle {
                s: root.s
                on: Flags.keepAwake
                onToggled: Flags.keepAwake = !Flags.keepAwake
            }
        }

        SectionLabel { s: root.s; text: "Displays" }

        Repeater {
            model: Hyprland.monitors ? Hyprland.monitors.values : []

            delegate: Item {
                id: dRow
                required property var modelData
                required property int index

                readonly property bool isFocused: root.focusedName === modelData.name
                readonly property var ipc: modelData.lastIpcObject

                width: content.width
                height: 30 * root.s

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2 * root.s
                    anchors.bottomMargin: 2 * root.s
                    radius: 9 * root.s
                    color: dHover.hovered ? Theme.frameBg
                        : (dRow.isFocused ? Qt.alpha(Theme.onGlow, 0.14) : "transparent")
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                HoverHandler { id: dHover }

                GlyphIcon {
                    id: dIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s
                    height: 16 * root.s
                    name: "monitor"
                    color: dRow.isFocused ? Theme.vermLit : Theme.iconDim
                    stroke: 1.7
                }

                Text {
                    anchors.left: dIcon.right
                    anchors.leftMargin: 12 * root.s
                    anchors.right: dCheck.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: dRow.modelData.name
                        + (dRow.ipc && dRow.ipc.width ? "   " + dRow.ipc.width + "×" + dRow.ipc.height : "")
                    color: dRow.isFocused ? Theme.cream : Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 11.5 * root.s
                    font.weight: dRow.isFocused ? Font.Bold : Font.Medium
                }

                GlyphIcon {
                    id: dCheck
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: dRow.isFocused
                    width: 15 * root.s
                    height: 15 * root.s
                    name: "check"
                    color: Theme.vermLit
                    stroke: 2
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("focusmonitor " + dRow.modelData.name)
                }
            }
        }

        Item { width: 1; height: 4 * root.s }
    }
}
