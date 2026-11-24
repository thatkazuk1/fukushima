pragma ComponentBehavior: Bound
import QtQuick
import "../config"
import "../services"

/**
 * Notch face for the usage limits: three small rings, one each for Codex,
 * Claude and Antigravity, each showing that provider's highest used percent.
 * A ring is iconDim below 80 percent, flame from 80 and vermilion from 95. A
 * provider with no data keeps a faint empty ring, so the face never shows a
 * missing provider as an error. A stale provider fades its arc.
 */
Row {
    id: root

    property real s: 1
    /** Ring diameter before the `s` scale. */
    property real ringSize: 14
    property bool bright: false

    spacing: 4 * s

    Repeater {
        model: Usage.providers

        RingGauge {
            id: ring
            required property var modelData

            readonly property real pct: Usage.peakOf(modelData)
            readonly property bool has: pct >= 0 && Usage.statusOf(modelData) !== "error"

            s: root.s
            size: root.ringSize
            stroke: 2.2
            outerPct: has ? pct : -1
            dim: !has
            idleColor: root.bright ? Theme.cream : Theme.iconDim
            opacity: Usage.statusOf(modelData) === "stale" ? 0.55 : 1
        }
    }
}
