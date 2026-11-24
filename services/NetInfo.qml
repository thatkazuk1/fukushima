pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../lib/net.js" as Net

/**
 * Live network vitals for the 波 WIFI surface: interface / IP / gateway, live
 * receive + send rates and session totals, router + internet latency with
 * packet loss, and the Wi-Fi band. Polling runs only while `open` is true — the
 * status poll (scripts/net-status.sh) every second, the band poll
 * (scripts/net-band.sh) every five. Opening primes both at once.
 *
 * The arithmetic (byte deltas, the rolling ping window, formatting) lives in
 * lib/net.js so it stays testable without a compositor.
 */
Singleton {
    id: root

    property bool open: false

    // --- raw ---
    property string iface: ""
    property string type: ""
    property string ipAddr: ""
    property string prefix: ""
    property string gateway: ""
    property string ssid: ""
    property int signalPct: -1
    property string linkRate: ""
    property string freq: ""
    property int linkSpeed: 0

    // --- derived (via lib/net.js) ---
    property var _tp: ({})
    property var _routerPings: []
    property var _internetPings: []
    property bool hasPingSamples: false

    readonly property real downRate: _tp.downRate || 0
    readonly property real upRate: _tp.upRate || 0
    readonly property real downTotal: _tp.downTotal || 0
    readonly property real upTotal: _tp.upTotal || 0
    readonly property real routerPing: Net.pingAvg(_routerPings)
    readonly property real internetPing: Net.pingAvg(_internetPings)
    readonly property int packetLoss: Net.pingLoss(_internetPings)

    readonly property string downRateText: Net.fmtRate(downRate)
    readonly property string upRateText: Net.fmtRate(upRate)
    readonly property string downTotalText: Net.fmtBytes(downTotal)
    readonly property string upTotalText: Net.fmtBytes(upTotal)
    readonly property string pingText: Net.fmtPing(internetPing, hasPingSamples)
    readonly property string routerPingText: Net.fmtPing(routerPing, hasPingSamples)
    readonly property string packetLossText: Net.fmtLoss(packetLoss, hasPingSamples)

    // --- band ---
    property string band: ""
    property var bandAvailable: []
    property string bandSelected: "auto"
    property bool bandBusy: false
    readonly property string bandTitle: Net.bandSectionTitle(bandSelected, band)

    readonly property int pingWindow: 5

    function prime() {
        root._tp = {};
        root._routerPings = [];
        root._internetPings = [];
        root.hasPingSamples = false;
        statusProc.running = true;
        bandProc.running = true;
    }

    function setBand(target) {
        if (bandBusy)
            return;
        root.bandBusy = true;
        root.bandSelected = target;
        setBandProc.command = ["bash", Config.hyprPath("scripts", "net-band.sh"), target];
        setBandProc.running = true;
    }

    onOpenChanged: {
        if (open)
            prime();
        else
            root.bandBusy = false;
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.open
        onTriggered: if (!statusProc.running) statusProc.running = true
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.open
        onTriggered: if (!bandProc.running && !root.bandBusy) bandProc.running = true
    }

    Process {
        id: statusProc
        command: ["bash", Config.hyprPath("scripts", "net-status.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var tab = lines[i].indexOf("\t");
                    if (tab > 0)
                        m[lines[i].slice(0, tab)] = lines[i].slice(tab + 1);
                }

                root.iface = m.iface || "";
                root.type = m.type || "";
                root.ipAddr = m.ip || "";
                root.prefix = m.prefix || "";
                root.gateway = m.gateway || "";
                root.ssid = m.ssid || "";
                root.signalPct = m.signal !== undefined ? parseInt(m.signal, 10) : -1;
                root.linkRate = m.rate || "";
                root.freq = m.freq || "";
                root.linkSpeed = m.speed !== undefined ? parseInt(m.speed, 10) || 0 : 0;

                if (m.rx_bytes !== undefined && m.tx_bytes !== undefined) {
                    root._tp = Net.throughput(root._tp,
                        { iface: root.iface, rx: parseFloat(m.rx_bytes), tx: parseFloat(m.tx_bytes) },
                        Date.now() / 1000);
                }

                var sawPing = m.router_ping_ms !== undefined || m.internet_ping_ms !== undefined;
                if (sawPing || root.hasPingSamples) {
                    root._routerPings = Net.pingPush(root._routerPings,
                        m.router_ping_ms !== undefined ? parseFloat(m.router_ping_ms) : null, root.pingWindow);
                    root._internetPings = Net.pingPush(root._internetPings,
                        m.internet_ping_ms !== undefined ? parseFloat(m.internet_ping_ms) : null, root.pingWindow);
                }
                if (sawPing)
                    root.hasPingSamples = true;
            }
        }
    }

    Process {
        id: bandProc
        command: ["bash", Config.hyprPath("scripts", "net-band.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var tab = lines[i].indexOf("\t");
                    if (tab < 1)
                        continue;
                    var k = lines[i].slice(0, tab);
                    var v = lines[i].slice(tab + 1).trim();
                    if (k === "band")
                        root.band = v;
                    else if (k === "available")
                        root.bandAvailable = v.length ? v.split(" ") : [];
                    else if (k === "selected" && !root.bandBusy)
                        root.bandSelected = v;
                }
            }
        }
    }

    Process {
        id: setBandProc
        stderr: StdioCollector { id: setBandErr }
        onExited: function (code) {
            root.bandBusy = false;
            bandProc.running = true;
            if (code !== 0)
                root.bandError(setBandErr.text.trim());
        }
    }

    signal bandError(string message)
}
