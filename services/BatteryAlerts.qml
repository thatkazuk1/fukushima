pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Battery notification latches, change-triggered by UPower (never polled). Low
 * battery escalates down the levels — 25% then 20% fire once each as a normal
 * warning, and 15% opens a critical announcement that repeats every ten minutes
 * until the battery is plugged in. The latch re-arms when the battery charges or
 * rises back above 25%. Full fires once when the battery reports fully charged,
 * so charge-limited systems (e.g. an 80% cut-off) announce at their actual full
 * point.
 *
 * A lazy singleton: `void BatteryAlerts.armed` from the shell's
 * Component.onCompleted forces it to instantiate and run the boot check, so a
 * machine that boots at 18% still announces.
 */
Singleton {
    id: root

    readonly property bool armed: true

    property int notifiedBelow: 100
    property bool fullNotified: false

    function note(urgency, summary, body) {
        noteProc.command = urgency.length > 0
            ? ["notify-send", "-a", "Fukushima", "-u", urgency, summary, body]
            : ["notify-send", "-a", "Fukushima", summary, body];
        noteProc.running = true;
    }

    /**
     * One-shot level crossings on the way down, lowest threshold first, so a
     * battery already below several levels (e.g. booting at 18%) only announces
     * the most urgent one it has passed — 20% there, never 25% and 20% together.
     * At or below the critical level the repeat timer takes over.
     */
    function check() {
        if (!Battery.present)
            return;
        if (!Battery.discharging || Battery.pct > 25) {
            root.notifiedBelow = 100;
            repeatTimer.stop();
            return;
        }
        var levels = [[15, "critical"], [20, "normal"], [25, "normal"]];
        for (var i = 0; i < levels.length; i++) {
            if (Battery.pct <= levels[i][0] && levels[i][0] < root.notifiedBelow) {
                root.notifiedBelow = levels[i][0];
                var critical = levels[i][1] === "critical";
                root.note(critical ? "critical" : "normal",
                    critical ? "Battery critical" : "Low battery",
                    Battery.pct + "% remaining — plug in your charger"
                    + (critical ? " now." : " soon."));
                break;
            }
        }
        if (Battery.pct <= 15 && !repeatTimer.running)
            repeatTimer.start();
    }

    Component.onCompleted: root.check()

    Process {
        id: noteProc
    }

    Timer {
        id: repeatTimer
        interval: 10 * 60 * 1000
        repeat: true
        onTriggered: {
            if (!Battery.present || !Battery.discharging || Battery.pct > 15) {
                stop();
                return;
            }
            root.note("critical", "Battery critical",
                Battery.pct + "% remaining — plug in your charger now.");
        }
    }

    Connections {
        target: Battery
        function onPctChanged() { root.check(); }
        function onDischargingChanged() { root.check(); }
        function onFullChanged() {
            if (!Battery.present)
                return;
            if (Battery.full && !root.fullNotified) {
                root.fullNotified = true;
                root.note("normal", "Battery full",
                    Battery.pct + "% — you can unplug.");
            } else if (!Battery.full) {
                root.fullNotified = false;
            }
        }
    }
}
