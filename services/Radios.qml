pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

/**
 * Real radio state for the pill's wifi and Bluetooth icons.
 *
 * Quickshell's Bluetooth and Networking backends keep their own copy of the
 * state, and that copy goes stale when bluetoothd or NetworkManager restarts:
 * the Bluetooth adapter then reads "disabled" while a device is connected, and
 * the wifi device list stays empty so the icon disappears. Quickshell has no
 * call to refresh either backend, so this singleton reads the real state from
 * scripts/radios.sh instead.
 *
 * A `dbus-monitor` watcher re-reads the state when bluetoothd or
 * NetworkManager changes owner (a restart) or reports a change. The re-read is
 * throttled to one run each second. A slow timer is the fallback if the
 * watcher stops.
 *
 * `bt` and `wifi` hold "none" (no hardware), "on" or "off". Both hold "" until
 * the first read lands; the pill then falls back to the Quickshell values.
 * `ethernet` is true while the route to the internet uses a wired device.
 */
Singleton {
    id: root

    property string bt: ""
    property string wifi: ""
    /** Signal of the connected wifi network, 0 to 1. Negative when unknown. */
    property real wifiSignal: -1
    /** True while the route to the internet uses a wired device. */
    property bool ethernet: false

    readonly property bool known: bt !== "" && wifi !== ""

    function refresh() {
        if (!pollProc.running)
            pollProc.running = true;
    }

    /** Switch the Bluetooth adapter power. Reads the real state, so it also works on a stale backend. */
    function toggleBt() {
        if (setProc.running || bt === "" || bt === "none")
            return;
        // BlueZ rejects power on while rfkill soft-blocks the controller, so unblock first.
        setProc.command = bt === "on"
            ? ["bluetoothctl", "power", "off"]
            : ["sh", "-c", "rfkill unblock bluetooth; bluetoothctl power on"];
        setProc.running = true;
    }

    /** Switch the wifi radio. */
    function toggleWifi() {
        if (setProc.running || wifi === "" || wifi === "none")
            return;
        setProc.command = ["nmcli", "radio", "wifi", wifi === "on" ? "off" : "on"];
        setProc.running = true;
    }

    Process {
        id: setProc
        onExited: root.refresh()
    }

    // Throttle, not debounce: a steady stream of signals must not delay the read.
    Timer {
        id: throttle
        interval: 1000
        onTriggered: root.refresh()
    }

    function scheduleRefresh() {
        if (!throttle.running)
            throttle.start();
    }

    Component.onCompleted: root.refresh()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: pollProc
        command: ["bash", Config.hyprPath("scripts", "radios.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                var bt = "";
                var wifi = "";
                var sig = -1;
                var eth = false;
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var kv = lines[i].split("\t");
                    if (kv.length < 2)
                        continue;
                    if (kv[0] === "bt")
                        bt = kv[1];
                    else if (kv[0] === "wifi")
                        wifi = kv[1];
                    else if (kv[0] === "wifi_signal")
                        sig = Math.max(0, Math.min(100, parseInt(kv[1]))) / 100;
                    else if (kv[0] === "eth")
                        eth = kv[1].trim() === "on";
                }
                // An empty reply means the script failed; keep the last good state.
                if (bt === "" || wifi === "")
                    return;
                root.bt = bt;
                root.wifi = wifi;
                root.wifiSignal = isNaN(sig) ? -1 : sig;
                root.ethernet = eth;
            }
        }
    }

    Process {
        id: watcher
        running: true
        command: ["dbus-monitor", "--system",
            "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.bluez'",
            "type='signal',sender='org.freedesktop.DBus',member='NameOwnerChanged',arg0='org.freedesktop.NetworkManager'",
            "type='signal',sender='org.bluez',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged'",
            "type='signal',sender='org.freedesktop.NetworkManager',interface='org.freedesktop.NetworkManager'"]
        stdout: SplitParser {
            // Each signal starts with a "signal " header line; ignore the body lines.
            onRead: (line) => {
                if (line.indexOf("signal ") === 0)
                    root.scheduleRefresh();
            }
        }
        onExited: () => watcher.running = true
    }
}
