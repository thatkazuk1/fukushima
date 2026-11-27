pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../../components"

/**
 * 量 USAGE surface: the LLM usage limits as ring gauges, one card per provider.
 * The weekly window is on the outer ring and a 5 hour window (else a second
 * weekly window) is on the inner ring, with the highest percent in the middle.
 * Every card has the same two centred lines, 5h and 7d. A line shows the
 * highest window of its period; a hover hint lists each window when a period
 * has more than one. A window with no reset time shows a dim dash. Under the ring sit the provider name and one line
 * for each window: label, used percent and the time until reset. Ring colour
 * follows the load (normal, flame from 80, vermilion from 95). A provider with
 * no data shows a faint empty ring and the word "no data"; the reason appears in
 * a hover hint, never as an error. A stale provider fades its rings and shows a
 * STALE tag. The header shows how old the collector's data is. All data comes
 * from the Usage singleton, which only reads the collector's JSON file.
 */
PillSurface {
    id: root

    mTop: 16
    mLeft: 19
    mRight: 19
    mBottom: 16

    implicitHeight: content.implicitHeight

    function tint(pct) {
        return pct >= 95 ? Theme.vermLit : (pct >= 80 ? Theme.flameGlow : Theme.cream);
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        Item {
            width: parent.width
            height: 22 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    text: "量"
                    color: Theme.cream
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "USAGE"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Usage.fileUpdatedAt > 0
                text: "updated " + Usage.ageOf(Usage.fileUpdatedAt)
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
            }
        }

        Row {
            id: cards
            width: parent.width
            topPadding: 14 * root.s
            spacing: 22 * root.s

            readonly property real cardW: (width - spacing * Math.max(0, Usage.providers.length - 1))
                / Math.max(1, Usage.providers.length)

            // The models are counts, so a file update keeps the delegates and
            // the ring arcs animate from the old value to the new one.
            Repeater {
                model: Usage.providers.length

                Column {
                    id: card
                    required property int index
                    readonly property var modelData: Usage.providers[index] || Usage.emptyProvider("", "")

                    readonly property string status: Usage.statusOf(modelData)
                    readonly property bool live: modelData.windows.length > 0
                    readonly property var outer: Usage.outerWindow(modelData)
                    readonly property var inner: Usage.innerWindow(modelData)
                    readonly property real peak: Usage.peakOf(modelData)

                    width: cards.cardW
                    spacing: 7 * root.s

                    readonly property string detail: Usage.detailText(modelData)

                    HoverHandler { id: hover }

                    Item {
                        width: parent.width
                        height: ring.height
                        // The hint must draw above the name and the lines below.
                        z: 1

                        RingGauge {
                            id: ring
                            anchors.horizontalCenter: parent.horizontalCenter
                            s: root.s
                            size: 70
                            stroke: 5.5
                            dim: !card.live
                            outerPct: card.outer ? card.outer.pct : -1
                            innerPct: card.inner ? card.inner.pct : -1
                            opacity: card.status === "stale" ? 0.55 : 1

                            Text {
                                anchors.centerIn: parent
                                text: card.live ? Math.round(card.peak) + "%" : "–"
                                color: card.live ? root.tint(card.peak) : Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 13 * root.s
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                            }
                        }

                        Tooltip {
                            s: root.s
                            placement: "below"
                            title: card.modelData.name
                            desc: card.live ? card.detail : card.modelData.reason
                            show: hover.hovered && (!card.live || card.detail.length > 0)
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 1 * root.s

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 6 * root.s

                            ProviderMark {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13 * root.s
                                height: 13 * root.s
                                provider: card.modelData.id
                                tint: card.live ? Theme.cream : Theme.dim
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.name
                                color: card.live ? Theme.cream : Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: card.status === "stale" ? "STALE · " + Usage.ageOf(card.modelData.updatedAt)
                                : (card.status === "error" ? "ERROR"
                                : (card.live ? card.modelData.plan : "no data"))
                            color: card.status === "error" ? Theme.vermLit
                                : (card.status === "stale" ? Theme.flameGlow : Theme.dim)
                            font.family: Theme.font
                            font.pixelSize: 8.5 * root.s
                            font.weight: Font.Bold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.1 * root.s
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 5 * root.s

                        Repeater {
                            model: 2

                            Item {
                                id: line
                                required property int index
                                readonly property var win: Usage.periodTop(card.modelData, index === 0)

                                width: card.width
                                height: 13 * root.s

                                // Fixed cell widths, so every card lines up under its ring.
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6 * root.s
                                    visible: card.live

                                    Text {
                                        width: 16 * root.s
                                        text: line.index === 0 ? "5h" : "7d"
                                        color: Theme.subtle
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.DemiBold
                                        anchors.baseline: pct.baseline
                                    }
                                    Text {
                                        id: pct
                                        width: 30 * root.s
                                        horizontalAlignment: Text.AlignRight
                                        text: line.win ? Math.round(line.win.pct) + "%" : "–"
                                        color: line.win ? root.tint(line.win.pct) : Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.Bold
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        width: 42 * root.s
                                        horizontalAlignment: Text.AlignRight
                                        text: line.win && line.win.resetsAt > 0
                                            ? Usage.resetShort(line.win.resetsAt) : "–"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 9.5 * root.s
                                        font.features: { "tnum": 1 }
                                        anchors.baseline: pct.baseline
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: 4 * root.s }
    }
}
