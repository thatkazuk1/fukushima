pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"

/**
 * 調 SOUND surface: the audio counterpart to the 画 DISPLAY surface, laid out the
 * same way omarchy Quattro's sound panel is — an OUTPUT block (volume fader over
 * the list of real sinks) then an INPUT block (mic fader over the list of real
 * sources). Tapping a device row makes it the Pipewire default; tapping a fader
 * icon mutes that side. Every interactive row carries a washi tooltip.
 *
 * Built on SettingsSurface so the row seam, hover tracking and keyboard nav
 * (Up/Down move rows, Left/Right adjust) come for free — the two faders register
 * as `scrub` rows and step 5% per notch. Screen brightness, vibrance, night
 * light and keep-awake live in ScreenSurface.
 */
SettingsSurface {
    id: root

    backSurface: ""
    implicitHeight: content.implicitHeight

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    /**
     * Output devices the user can make default: real sinks only, never the
     * per-app playback streams. Sorted by label so the list order stays stable
     * as nodes appear and vanish.
     */
    readonly property var outputSinks: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && n.isSink && !n.isStream && n.audio)
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    /**
     * Input devices the user can make default: real sources only. The sink
     * monitors that Pipewire exposes alongside real mics also match isSink=false,
     * so they are dropped by name to keep the list to actual capture devices.
     */
    readonly property var inputSources: {
        void Pipewire.nodes.values;
        var out = [];
        var all = Pipewire.nodes.values;
        for (var i = 0; i < all.length; i++) {
            var n = all[i];
            if (n && !n.isSink && !n.isStream && n.audio && !/monitor/i.test(n.name || ""))
                out.push(n);
        }
        out.sort((a, b) => root.deviceLabel(a).localeCompare(root.deviceLabel(b)));
        return out;
    }

    function deviceLabel(node) {
        if (!node)
            return "";
        return node.description || node.nickname || node.name || "";
    }

    PwObjectTracker {
        objects: [root.sink, root.source].concat(root.outputSinks).concat(root.inputSources).filter(Boolean)
    }

    // --- keyboard row registry -------------------------------------------

    rows: [
        { item: outRow, kind: "scrub", bump: function (d) { outRow.step(d * 5); } },
        { item: inRow, kind: "scrub", bump: function (d) { inRow.step(d * 5); } }
    ]

    // --- pieces --------------------------------------------------------

    /** One device in an OUTPUT / INPUT list; tap to make it the default. */
    component DeviceRow: Item {
        id: drow
        property var node
        property bool current: false
        property string glyph: "speaker"
        signal picked()

        width: parent ? parent.width : 0
        height: 30 * root.s

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 2 * root.s
            anchors.bottomMargin: 2 * root.s
            radius: 9 * root.s
            color: dHover.hovered ? Theme.frameBg
                : (drow.current ? Qt.alpha(Theme.onGlow, 0.14) : "transparent")
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        HoverHandler { id: dHover }

        GlyphIcon {
            id: dIcon
            anchors.left: parent.left
            anchors.leftMargin: 16 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 15 * root.s
            height: 15 * root.s
            name: drow.glyph
            color: drow.current ? Theme.vermLit : Theme.iconDim
            stroke: 1.7
        }

        Text {
            anchors.left: dIcon.right
            anchors.leftMargin: 12 * root.s
            anchors.right: dCheck.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.deviceLabel(drow.node)
            color: drow.current ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 11.5 * root.s
            font.weight: drow.current ? Font.Bold : Font.Medium
        }

        GlyphIcon {
            id: dCheck
            anchors.right: parent.right
            anchors.rightMargin: 14 * root.s
            anchors.verticalCenter: parent.verticalCenter
            visible: drow.current
            width: 15 * root.s
            height: 15 * root.s
            name: "check"
            color: Theme.vermLit
            stroke: 2
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: drow.picked()
        }

        Tooltip {
            s: root.s
            placement: "below"
            title: root.deviceLabel(drow.node)
            desc: drow.current ? "Current device" : "Switch to this device"
            show: dHover.hovered
        }
    }

    // --- layout ------------------------------------------------------

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "調"
            title: "SOUND"
            showBack: false
        }

        Item { width: 1; height: 8 * root.s }

        SectionLabel {
            s: root.s
            text: "Output"
            value: root.sink && root.sink.audio
                ? (root.sink.audio.muted ? "muted" : Math.round(root.sink.audio.volume * 100) + "%")
                : ""
        }

        FaderRow {
            id: outRow
            surface: root
            labelWidth: 46 * root.s
            icon: (root.sink && root.sink.audio && root.sink.audio.muted) ? "speaker-off" : "speaker"
            label: "Volume"
            on: root.sink && root.sink.audio ? !root.sink.audio.muted : true
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            iconTappable: true
            tip: "Output volume"
            tipDesc: "Scroll or drag · tap icon to mute"
            onMoved: (v) => { if (root.sink && root.sink.audio) root.sink.audio.volume = v; }
            onIconTapped: { if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted; }
        }

        Repeater {
            model: root.outputSinks

            delegate: DeviceRow {
                required property var modelData
                node: modelData
                current: root.sink === modelData
                glyph: "speaker"
                onPicked: if (modelData) Pipewire.preferredDefaultAudioSink = modelData
            }
        }

        SectionLabel {
            s: root.s
            text: "Input"
            value: root.source && root.source.audio
                ? (root.source.audio.muted ? "muted" : Math.round(root.source.audio.volume * 100) + "%")
                : ""
        }

        FaderRow {
            id: inRow
            surface: root
            labelWidth: 46 * root.s
            icon: (root.source && root.source.audio && root.source.audio.muted) ? "mic-off" : "mic"
            label: "Mic"
            on: root.source && root.source.audio ? !root.source.audio.muted : true
            value: root.source && root.source.audio ? root.source.audio.volume : 0
            iconTappable: true
            tip: "Input volume"
            tipDesc: "Microphone gain · tap icon to mute"
            onMoved: (v) => { if (root.source && root.source.audio) root.source.audio.volume = v; }
            onIconTapped: { if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted; }
        }

        Repeater {
            model: root.inputSources

            delegate: DeviceRow {
                required property var modelData
                node: modelData
                current: root.source === modelData
                glyph: "mic"
                onPicked: if (modelData) Pipewire.preferredDefaultAudioSource = modelData
            }
        }

        Item { width: 1; height: 6 * root.s }
    }
}
