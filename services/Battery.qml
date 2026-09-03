pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * Laptop-battery state for the pill, sourced from UPower's display device and
 * gated so a desktop without a battery reports `present` false (the hover
 * cluster and 蓄 surface stay hidden). Exposes percentage, charge state, a
 * signed draw/charge wattage, capacity and optional health, plus a formatted
 * time-to-empty/full string. `low` flags a discharging battery at or below 20%.
 *
 * Wear / degradation (`design`, `wearPct`, `cycleCount`) is read from sysfs —
 * UPower over Quickshell exposes the current full capacity but not the design
 * capacity or the cycle count. Health is then `full / design`
 * (https://alchemmist.xyz/articles/battery-degradation/), preferring the sysfs
 * figures and falling back to UPower's own.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    readonly property bool present: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real frac: dev ? Math.max(0, Math.min(1, dev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool full: state === UPowerDeviceState.FullyCharged || pct >= 100
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool low: !charging && pct <= 20

    readonly property real rateW: !dev ? 0
        : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    readonly property bool healthSupported: dev ? dev.healthSupported : false
    readonly property int health: dev ? Math.round(dev.healthPercentage) : 0
    readonly property string model: dev ? (dev.model || "") : ""

    // --- wear / degradation (sysfs) ---
    property real designWh: 0
    property real fullWh: 0
    property int cycleCount: -1

    readonly property bool wearSupported: designWh > 0 && fullWh > 0
    /** Percent of the original design capacity that has been lost. */
    readonly property real wearPct: wearSupported
        ? Math.max(0, Math.min(100, (1 - fullWh / designWh) * 100)) : 0
    /** full / design as a percent — the battery's remaining capacity health. */
    readonly property int healthPct: wearSupported ? Math.round(100 * fullWh / designWh)
        : (healthSupported ? health : 0)

    onChargingChanged: wearProc.running = true

    Process {
        id: wearProc
        running: root.present
        command: ["sh", "-c",
            "for b in /sys/class/power_supply/BAT*/; do [ -d \"$b\" ] || continue; "
            + "if [ -r \"${b}energy_full_design\" ]; then "
            + "d=$(cat \"${b}energy_full_design\"); f=$(cat \"${b}energy_full\" 2>/dev/null || echo 0); "
            + "awk -v d=\"$d\" -v f=\"$f\" 'BEGIN{printf \"DESIGN %.3f\\nFULL %.3f\\n\", d/1e6, f/1e6}'; "
            + "elif [ -r \"${b}charge_full_design\" ]; then "
            + "cd=$(cat \"${b}charge_full_design\"); cf=$(cat \"${b}charge_full\" 2>/dev/null || echo 0); "
            + "v=$(cat \"${b}voltage_min_design\" 2>/dev/null || cat \"${b}voltage_now\" 2>/dev/null || echo 0); "
            + "awk -v cd=\"$cd\" -v cf=\"$cf\" -v v=\"$v\" 'BEGIN{printf \"DESIGN %.3f\\nFULL %.3f\\n\", cd/1e6*v/1e6, cf/1e6*v/1e6}'; "
            + "fi; "
            + "[ -r \"${b}cycle_count\" ] && echo \"CYCLES $(cat \"${b}cycle_count\")\"; "
            + "break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split(" ");
                    if (p[0] === "DESIGN")
                        root.designWh = parseFloat(p[1]) || 0;
                    else if (p[0] === "FULL")
                        root.fullWh = parseFloat(p[1]) || 0;
                    else if (p[0] === "CYCLES")
                        root.cycleCount = parseInt(p[1], 10);
                }
            }
        }
    }

    /** Capacity and cycle count drift slowly; a five-minute re-read is plenty. */
    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: root.present
        onTriggered: wearProc.running = true
    }

    readonly property bool hasTime: !dev ? false
        : (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false))
    readonly property string timeStr: !dev ? ""
        : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel: charging ? "Charging"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC"))

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m";
    }
}
