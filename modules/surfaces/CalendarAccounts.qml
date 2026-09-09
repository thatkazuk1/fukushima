pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../../config"
import "../../services"
import "../../components"

/**
 * 暦 CALENDARS sub-surface: connect Google accounts whose events the calendar
 * grid then shows read-only beside the local ones. Reached from the calendar
 * header and folds back to it on the back chevron or an empty click.
 *
 * All the OAuth and API work is in scripts/gcal.py, driven by the Gcal
 * singleton; this is just the list of connected accounts (each with a
 * disconnect) and the connect flow. The Client ID / secret fields only show
 * until the first account is linked — after that gcal.py reuses the stored
 * client.json, so linking accounts two and three is one button. `Gcal.authLog`
 * carries the live step ("opening browser…", "connected a@b.com", an error).
 */
SettingsSurface {
    id: root

    rows: []
    implicitHeight: content.implicitHeight

    /**
     * Show the credential fields until the first account is actually linked —
     * not merely until client.json exists — so a wrong client id/secret can be
     * re-entered and overwritten on a retry. Pre-filled with what's stored.
     */
    readonly property bool needsClient: Gcal.accounts.length === 0

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "暦"
            title: "CALENDARS"
            showBack: true
        }

        Item { width: 1; height: 12 * root.s }

        // --- connected accounts ------------------------------------------

        Text {
            width: parent.width
            visible: Gcal.accounts.length === 0
            text: "No Google account linked yet."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.italic: true
            bottomPadding: 10 * root.s
        }

        Repeater {
            model: Gcal.accounts

            SettingsRow {
                id: acctRow
                required property var modelData
                required property int index
                surface: root
                icon: "inbox"
                name: acctRow.modelData.email || "account"
                sub: {
                    var st = Gcal.accountStatus.filter(function (a) {
                        return a.email === acctRow.modelData.email;
                    })[0];
                    if (st && !st.ok)
                        return st.error || "sync error";
                    return Gcal.ready ? "syncing ok" : "…";
                }
                last: acctRow.index === Gcal.accounts.length - 1

                Rectangle {
                    width: 24 * root.s
                    height: 24 * root.s
                    radius: Motion.rSmall * root.s
                    color: dcArea.containsMouse ? Qt.alpha(Theme.vermLit, 0.14) : "transparent"

                    GlyphIcon {
                        anchors.centerIn: parent
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "close"
                        color: dcArea.containsMouse ? Theme.vermLit : Theme.iconDim
                        stroke: 1.7
                    }

                    MouseArea {
                        id: dcArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Gcal.disconnect(acctRow.modelData.email)
                    }
                }
            }
        }

        Item { width: 1; height: 14 * root.s }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item { width: 1; height: 12 * root.s }

        // --- connect a new account -------------------------------------

        Text {
            width: parent.width
            text: root.needsClient ? "CONNECT — PASTE YOUR OAUTH CLIENT" : "CONNECT ANOTHER ACCOUNT"
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2 * root.s
            bottomPadding: 8 * root.s
        }

        Column {
            width: parent.width
            visible: root.needsClient
            spacing: 8 * root.s
            bottomPadding: 10 * root.s

            Item {
                width: parent.width
                height: 26 * root.s

                TextField {
                    id: idField
                    anchors.fill: parent
                    background: null
                    padding: 0
                    leftPadding: 2 * root.s
                    verticalAlignment: TextInput.AlignVCenter
                    text: Gcal.clientId
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    placeholderText: "Client ID (…apps.googleusercontent.com)"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.faint
                    opacity: idField.activeFocus ? 0.7 : 0.2
                }
            }

            Item {
                width: parent.width
                height: 26 * root.s

                TextField {
                    id: secretField
                    anchors.fill: parent
                    background: null
                    padding: 0
                    leftPadding: 2 * root.s
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    text: Gcal.clientSecret
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    placeholderText: "Client secret"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.faint
                    opacity: secretField.activeFocus ? 0.7 : 0.2
                }
            }
        }

        Rectangle {
            id: connectBtn
            width: parent.width
            height: 30 * root.s
            radius: Motion.rSmall * root.s
            readonly property bool armed: !Gcal.connecting
                && (!root.needsClient
                    || (idField.text.trim().length > 0 && secretField.text.trim().length > 0))
            color: connectArea.containsMouse && armed ? Qt.alpha(Theme.vermLit, 0.22)
                : (armed ? Qt.alpha(Theme.vermLit, 0.12) : Theme.frameBg)
            border.width: 1
            border.color: connectBtn.armed ? Qt.alpha(Theme.vermLit, 0.5) : Theme.frameBorder
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            Text {
                anchors.centerIn: parent
                text: Gcal.connecting ? "waiting for browser…" : "Connect with Google"
                color: connectBtn.armed ? Theme.vermLit : Theme.iconDim
                font.family: Theme.font
                font.pixelSize: 11.5 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 0.3 * root.s
            }

            MouseArea {
                id: connectArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: connectBtn.armed ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!connectBtn.armed)
                        return;
                    Gcal.connect(idField.text, secretField.text);
                }
            }
        }

        Text {
            width: parent.width
            visible: Gcal.authLog.length > 0
            topPadding: 8 * root.s
            text: Gcal.authLog
            color: Gcal.authLog.indexOf("connected ") === 0 ? Theme.flameGlow : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            topPadding: 8 * root.s
            text: root.needsClient
                ? "One Google Cloud “Desktop app” client covers every account — see docs/GCAL-SETUP.md."
                : "A browser tab opens for each account. Events are read-only."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            wrapMode: Text.Wrap
            lineHeight: 1.25
        }
    }
}
