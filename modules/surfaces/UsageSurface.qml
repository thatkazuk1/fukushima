pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../../components"

/**
 * 量 USAGE surface: the LLM usage limits as ring gauges, one card per provider.
 * A provider with a session and a weekly window shows the weekly window on the
 * outer ring and the 5 hour session on the inner ring, with the larger of the
 * two percents in the middle. Under the ring sit the provider name and one line
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
            spacing: 8 * root.s

            readonly property real cardW: (width - spacing * Math.max(0, Usage.providers.length - 1))
                / Math.max(1, Usage.providers.length)

            Repeater {
                model: Usage.providers

                Column {
                    id: card
                    required property var modelData

                    readonly property string status: Usage.statusOf(modelData)
                    readonly property bool live: modelData.windows.length > 0
                    readonly property var outer: Usage.outerWindow(modelData)
                    readonly property var inner: Usage.innerWindow(modelData)
                    readonly property real peak: Usage.peakOf(modelData)

                    width: cards.cardW
                    spacing: 7 * root.s

                    HoverHandler { id: hover }

                    Item {
                        width: parent.width
                        height: ring.height

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
                            desc: card.live ? "" : card.modelData.reason
                            show: hover.hovered && !card.live
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 1 * root.s

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: card.modelData.name
                            color: card.live ? Theme.cream : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 11.5 * root.s
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: card.status === "stale" ? "STALE · " + Usage.ageOf(card.modelData.updatedAt)
                                : (card.status === "error" ? "ERROR"
                                : (card.live ? card.modelData.plan : "no data"))
                            visible: text.length > 0
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
                        spacing: 2 * root.s

                        Repeater {
                            model: card.modelData.windows

                            Item {
                                id: row
                                required property var modelData

                                width: parent.width
                                height: 13 * root.s

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.short + " " + Math.round(row.modelData.pct) + "%"
                                    color: root.tint(row.modelData.pct)
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Usage.resetShort(row.modelData.resetsAt)
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9.5 * root.s
                                    font.features: { "tnum": 1 }
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
