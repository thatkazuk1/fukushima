import QtQuick
import QtQuick.Effects
import "../config"

/**
 * Monochrome provider mark for the usage notch, tinted with a pill colour. The
 * SVG files are white and live in assets/marks (see SOURCE.md there). A
 * provider without a file, or with a file that fails to load, shows its first
 * letter.
 */
Item {
    id: root

    property string provider: ""
    property color tint: Theme.cream

    readonly property var files: ({ codex: "openai", claude: "claude", antigravity: "antigravity" })
    readonly property string file: files[provider] || ""

    implicitWidth: 12
    implicitHeight: 12

    Image {
        id: img
        anchors.fill: parent
        visible: false
        source: root.file.length > 0 ? Qt.resolvedUrl("../assets/marks/" + root.file + ".svg") : ""
        sourceSize: Qt.size(Math.ceil(width * 3), Math.ceil(height * 3))
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    MultiEffect {
        anchors.fill: img
        source: img
        visible: img.status === Image.Ready
        colorization: 1
        colorizationColor: root.tint
        brightness: 0
    }

    Text {
        anchors.centerIn: parent
        visible: root.file.length === 0 || img.status === Image.Error
        text: root.provider.charAt(0).toUpperCase()
        color: root.tint
        font.family: Theme.font
        font.pixelSize: root.height * 0.9
        font.weight: Font.Bold
    }
}
