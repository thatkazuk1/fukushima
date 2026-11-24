pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import "../../config"
import "../../components"

/**
 * Polkit authentication agent. It replaces hyprpolkitagent, so the password
 * prompt uses the same palette, font and card material as the pill.
 *
 * The agent registers with polkit for this session. When a program asks for
 * authentication, `agent.flow` is set and one Overlay window opens on the
 * focused monitor. The window takes exclusive keyboard focus. A press on the
 * backdrop does not dismiss the prompt, because a security prompt must end
 * with an explicit Authenticate or Cancel.
 */
Scope {
    id: root

    readonly property var flow: agent ? agent.flow : null
    readonly property bool shown: flow !== null

    /**
     * A config reload starts the new agent before the old one leaves the bus,
     * so the first registration can fail with "agent already exists". While
     * unregistered, a timer destroys and creates the agent again. The path
     * of an agent cannot change, so a new object is the only way to retry.
     */
    Loader {
        id: agentLoader
        sourceComponent: PolkitAgent {}
    }
    readonly property var agent: agentLoader.item

    Timer {
        interval: 1500
        repeat: true
        running: !root.agent || !root.agent.isRegistered
        onTriggered: {
            agentLoader.active = false;
            agentLoader.active = true;
        }
    }

    PanelWindow {
        id: win

        readonly property var focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        readonly property var target: {
            for (var i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === focusedName)
                    return Quickshell.screens[i];
            }
            return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        }
        readonly property real s: target ? (target.height / 1080) * Flags.uiScale : 1

        screen: target
        visible: root.shown
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fukushima-auth"
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
            opacity: win.visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            MouseArea { anchors.fill: parent }
        }

        Rectangle {
            id: card

            readonly property var f: root.flow
            readonly property real s: win.s
            readonly property var ids: f ? f.identities : []
            readonly property string who: f && f.selectedIdentity ? card.nameOf(f.selectedIdentity) : ""

            /** The display name can be a raw account comment such as ",,,". Use the first filled part, else the account name. */
            function nameOf(id) {
                var parts = String(id.displayName || "").split(",").map(function(p) { return p.trim(); });
                var first = parts.filter(function(p) { return p.length > 0; })[0];
                return first || String(id.name || "");
            }
            readonly property string prompt: {
                var p = f ? String(f.inputPrompt || "") : "";
                p = p.replace(/\s*:\s*$/, "");
                return p.length > 0 ? p : "Password";
            }
            readonly property string note: {
                if (!f) return "";
                if (String(f.supplementaryMessage || "").length > 0) return String(f.supplementaryMessage);
                return f.failed ? "That password did not work. Try again." : "";
            }
            readonly property bool noteIsError: f ? (f.supplementaryIsError || f.failed) : false

            anchors.centerIn: parent
            width: 400 * s
            height: col.implicitHeight + 40 * s
            radius: 22 * s
            border.width: 1
            border.color: Theme.border
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Theme.cardTop, Math.max(0.94, Flags.pillOpacity)) }
                GradientStop { position: 1.0; color: Qt.alpha(Theme.cardBot, Math.max(0.94, Flags.pillOpacity)) }
            }
            layer.enabled: win.visible
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, Theme.shadowOpacity)
                shadowBlur: 0.8
                shadowVerticalOffset: 4 * card.s
            }

            opacity: win.visible ? 1 : 0
            scale: win.visible ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
            Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }

            // Top sheen, same as the pill body.
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 1
                anchors.leftMargin: card.radius * 0.6
                anchors.rightMargin: card.radius * 0.6
                height: 1
                color: Theme.sheen
            }

            function submit() {
                if (!f) return;
                f.submit(pass.text);
                pass.text = "";
            }

            Connections {
                target: card.f
                function onIsResponseRequiredChanged() {
                    if (card.f && card.f.isResponseRequired) {
                        pass.text = "";
                        pass.input.forceActiveFocus();
                    }
                }
            }

            onFChanged: {
                pass.text = "";
                if (f) pass.input.forceActiveFocus();
            }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20 * card.s
                spacing: 12 * card.s

                Row {
                    spacing: 12 * card.s

                    Rectangle {
                        id: tile
                        width: 34 * card.s
                        height: 34 * card.s
                        radius: 11 * card.s
                        color: Theme.tileBg
                        border.width: 1
                        border.color: Theme.border

                        Rectangle {
                            anchors.centerIn: parent
                            width: 9 * card.s
                            height: 9 * card.s
                            radius: 2 * card.s
                            rotation: 45
                            color: Theme.vermLit
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3 * card.s

                        Text {
                            text: "AUTHENTICATION"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 8.5 * card.s
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.4 * card.s
                        }
                        Text {
                            text: card.who.length > 0 ? "as " + card.who : "Administrator"
                            color: Theme.cream
                            font.family: Theme.font
                            font.pixelSize: 12.5 * card.s
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: card.f ? card.f.message : ""
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 11.5 * card.s
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                // One chip for each identity when polkit offers more than one.
                Row {
                    visible: card.ids.length > 1
                    spacing: 6 * card.s

                    Repeater {
                        model: card.ids

                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool picked: card.f && card.f.selectedIdentity === modelData

                            height: 20 * card.s
                            width: chipText.implicitWidth + 18 * card.s
                            radius: 999
                            color: Theme.tileBg
                            border.width: 1
                            border.color: picked ? Theme.verm : Theme.border

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: card.nameOf(chip.modelData)
                                color: chip.picked ? Theme.vermLit : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 9.5 * card.s
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: card.f.selectedIdentity = chip.modelData
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: pass.height + 20 * card.s
                    radius: 13 * card.s
                    color: Theme.tileBg
                    border.width: 1
                    border.color: pass.input.activeFocus ? Theme.verm : Theme.border
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    SearchField {
                        id: pass
                        s: card.s
                        kanji: "鍵"
                        placeholder: card.prompt
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14 * card.s
                        anchors.rightMargin: 14 * card.s
                        anchors.verticalCenter: parent.verticalCenter
                        onAccepted: card.submit()
                        onDismissed: if (card.f) card.f.cancel()
                        Component.onCompleted: input.echoMode = Qt.binding(function() {
                            return card.f && card.f.responseVisible ? TextInput.Normal : TextInput.Password;
                        })
                    }
                }

                Text {
                    width: parent.width
                    visible: card.note.length > 0
                    text: card.note
                    color: card.noteIsError ? Theme.vermLit : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 10.5 * card.s
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8 * card.s

                    Rectangle {
                        height: 28 * card.s
                        width: cancelText.implicitWidth + 28 * card.s
                        radius: 999
                        color: Theme.tileBg
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            id: cancelText
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11 * card.s
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (card.f) card.f.cancel()
                        }
                    }

                    Rectangle {
                        height: 28 * card.s
                        width: okText.implicitWidth + 28 * card.s
                        radius: 999
                        color: Theme.verm
                        border.width: 1
                        border.color: Theme.vermLit

                        Text {
                            id: okText
                            anchors.centerIn: parent
                            text: "Authenticate"
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 11 * card.s
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.submit()
                        }
                    }
                }
            }
        }
    }
}
