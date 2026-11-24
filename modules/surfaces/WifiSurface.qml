pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../../config"
import "../../services"
import "../../components"

/**
 * 波 WIFI surface. Mirrors omarchy Quattro's network panel in Fukushima's
 * language: a live vitals grid (ping / packet loss, receive + send rates,
 * session totals, IP / gateway) fed by the Network service, a Wi-Fi band
 * selector, QR sharing and an inline speed test, over the existing signal-sorted
 * network list with its connect / disconnect / forget / password flow.
 *
 * Standalone root surface — Escape and the backdrop dismiss it; the pill body
 * provides the material, this item draws no background.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 16
    mRight: 16
    mBottom: 13

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property string wifiIface: wifiDev ? (wifiDev.name || "wlan0") : "wlan0"
    // Radios reads the real radio state; Quickshell's copy can go stale (see services/Radios.qml).
    readonly property bool wifiOn: Radios.wifi !== "" ? Radios.wifi === "on"
        : ((typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false)
    readonly property var nets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var netsSorted: nets.slice().sort(function(a, b) {
        var ar = a && a.connected ? 2 : (a && root.knownProfiles[a.name] === true ? 1 : 0);
        var br = b && b.connected ? 2 : (b && root.knownProfiles[b.name] === true ? 1 : 0);
        if (ar !== br)
            return br - ar;
        return ((b ? b.signalStrength : 0) || 0) - ((a ? a.signalStrength : 0) || 0);
    })
    readonly property var activeNet: nets.find(function(n) { return n && n.connected }) || null
    readonly property string statusText: !wifiOn ? "Off"
        : (activeNet ? (activeNet.name || "Connected") : "Not connected")

    property var securityMap: ({})
    property var knownProfiles: ({})
    property string expandedSsid: ""
    property bool connecting: false
    property bool connectFailed: false
    property string connFailReason: ""
    property bool scanning: false

    /** Detail line under the connected row: IPv4 address plus band and bitrate from nmcli. */
    property string connIp: ""
    property string connBandRate: ""
    readonly property string connDetail: {
        var p = [];
        if (connIp.length) p.push(connIp);
        if (connBandRate.length) p.push(connBandRate);
        return p.join(" · ");
    }

    /**
     * SSID of the saved network whose stored password is currently shown, plus
     * the revealed secret itself. Keying both to one SSID keeps the reveal local
     * to the row the user asked about and lets `revealResolved` distinguish "not
     * yet read" from "read but empty" so an open profile shows a clear message.
     */
    property string revealedSsid: ""
    property string revealedPw: ""
    property bool revealResolved: false

    /**
     * Draft of the password being typed for `expandedSsid`. Lives on the root so
     * the field can restore itself from the draft if the keyed list model swaps
     * the delegate's network object under it on a rescan.
     */
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    implicitHeight: listFrame.y + listFrame.height

    function isSecured(ssid) {
        var sec = securityMap[ssid];
        return sec !== undefined && sec !== "" && sec !== "--";
    }

    function refresh() {
        secProc.running = true;
        profProc.running = true;
        if (root.wifiDev)
            detailProc.running = true;
    }

    /**
     * Splits one `nmcli -t` line at its last unescaped colon and unescapes the
     * leading field. Returns null for lines without a field separator.
     */
    function splitTerse(line) {
        for (var k = line.length - 1; k >= 0; k--) {
            if (line[k] === ":" && (k === 0 || line[k - 1] !== "\\"))
                return { head: line.slice(0, k).replace(/\\:/g, ":"), tail: line.slice(k + 1) };
        }
        return null;
    }

    /**
     * Click dispatch for a network row. A connected or saved network expands the
     * inline confirm row (disconnect/connect plus forget) rather than acting at
     * once; an open unknown network connects directly; an unknown secured network
     * expands the password row. Tapping the open row again collapses it.
     */
    function activateNetwork(net) {
        if (!net)
            return;
        var ssid = net.name || "";
        if (expandedSsid === ssid && ssid.length) {
            expandedSsid = "";
            return;
        }
        if (net.connected || knownProfiles[ssid] === true) {
            connectFailed = false;
            pwDraft = "";
            expandedSsid = ssid;
            return;
        }
        if (!isSecured(ssid)) {
            expandedSsid = "";
            if (typeof net.connect === "function")
                net.connect();
            refresh();
            return;
        }
        connectFailed = false;
        pwDraft = "";
        expandedSsid = ssid;
    }

    /**
     * Connects a saved profile from its confirm row. Known profiles connect by
     * name through the device so no password prompt is needed. The row shows a
     * spinner until the active network lands or the safety timer gives up.
     */
    function connectKnown(net) {
        if (!net)
            return;
        expandedSsid = "";
        connecting = true;
        connectFailed = false;
        attemptSsid = net.name || "";
        connSpinTimer.restart();
        if (typeof net.connect === "function")
            net.connect();
        refresh();
    }

    function disconnectNetwork(net) {
        if (!net)
            return;
        expandedSsid = "";
        if (typeof net.disconnect === "function")
            net.disconnect();
        refresh();
    }

    /**
     * Drops the saved connection profile for `ssid`. The SSID is passed as its
     * own argv element so an odd character can neither break nor inject the
     * command. The list refreshes once nmcli exits.
     */
    function forgetNetwork(ssid) {
        if (forgetProc.running || !ssid.length)
            return;
        expandedSsid = "";
        forgetProc.command = ["nmcli", "connection", "delete", "id", ssid];
        forgetProc.running = true;
    }

    /**
     * Reveals the stored password of a saved profile, or hides it again if the
     * same row is already showing. NetworkManager lets the owning user read their
     * own saved secret without root, so this runs unprivileged. The SSID is
     * passed as its own argv element so an odd character can neither break nor
     * inject the command.
     */
    function revealPassword(ssid) {
        if (!ssid.length)
            return;
        if (revealedSsid === ssid) {
            hidePassword();
            return;
        }
        revealedSsid = ssid;
        revealedPw = "";
        revealResolved = false;
        revealProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "id", ssid];
        revealProc.running = true;
    }

    function hidePassword() {
        revealedSsid = "";
        revealedPw = "";
        revealResolved = false;
    }

    /**
     * Connects via `nmcli --ask`, feeding the password through stdin so the
     * secret never appears in the process command line (`/proc/<pid>/cmdline`
     * is world-readable for the whole connection attempt).
     */
    function connectWithPassword(ssid, pw) {
        if (connProc.running || !pw.length)
            return;
        connecting = true;
        connectFailed = false;
        connFailReason = "";
        attemptSsid = ssid;
        attemptWasKnown = knownProfiles[ssid] === true;
        pendingPw = pw;
        connProc.command = ["nmcli", "--ask", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    /**
     * Reload pulse: forces a fresh nmcli rescan and spins the control for up to
     * 10s. The device scanner already runs while the surface is open, so the
     * list never empties; this only refreshes results and drives the spinner.
     */
    function startScan() {
        if (!wifiOn)
            return;
        scanning = true;
        rescanProc.running = true;
        scanTimer.restart();
    }

    function stopScan() {
        scanning = false;
        scanTimer.stop();
    }

    onActiveChanged: {
        if (active) {
            refresh();
            startScan();
        } else {
            stopScan();
            expandedSsid = "";
            connecting = false;
            connSpinTimer.stop();
            connectFailed = false;
            hidePassword();
            qrOpen = false;
            speedOpen = false;
        }
    }

    onWifiOnChanged: if (!wifiOn) stopScan()

    onExpandedSsidChanged: if (revealedSsid !== expandedSsid) hidePassword()

    /** The known-profile spinner ends when the attempted network reports connected; the detail line follows every active-network change. */
    onActiveNetChanged: {
        if (root.activeNet && root.attemptSsid.length && (root.activeNet.name || "") === root.attemptSsid) {
            root.connecting = false;
            connSpinTimer.stop();
        }
        if (root.active && root.wifiDev)
            detailProc.running = true;
    }

    Binding {
        target: root.wifiDev
        property: "scannerEnabled"
        value: root.active && root.wifiOn
        when: root.wifiDev !== null
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: root.stopScan()
    }

    /** Safety net for the known-profile spinner when a connect silently never lands. */
    Timer {
        id: connSpinTimer
        interval: 10000
        onTriggered: root.connecting = false
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                root.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = root.splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                root.knownProfiles = set;
            }
        }
    }

    /**
     * Connected-network detail: band and bitrate of the ACTIVE nmcli row plus the
     * interface IPv4, marker-prefixed so a missing half can't shift the parse.
     */
    Process {
        id: detailProc
        command: ["sh", "-c",
            "nmcli -t -f ACTIVE,BAND,RATE dev wifi list | awk -F: '$1==\"yes\"{print \"BR \" $2 \" \" $3}'; "
            + "ip -4 -o addr show dev \"$1\" scope global | awk '{split($4,a,\"/\"); print \"IP \" a[1]; exit}'",
            "sh", root.wifiIface]
        stdout: StdioCollector {
            onStreamFinished: {
                var br = "";
                var ip = "";
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("BR ") === 0)
                        br = lines[i].slice(3).trim();
                    else if (lines[i].indexOf("IP ") === 0)
                        ip = lines[i].slice(3).trim();
                }
                root.connBandRate = br;
                root.connIp = ip;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector { id: connErr }
        onStarted: {
            write(root.pendingPw + "\n");
            root.pendingPw = "";
        }
        onExited: function(exitCode) {
            root.connecting = false;
            if (exitCode === 0) {
                root.expandedSsid = "";
                root.pwDraft = "";
                root.connectFailed = false;
                root.connFailReason = "";
                root.refresh();
            } else {
                root.connectFailed = true;
                var err = connErr.text.split("\n").filter(function(l) { return l.trim().length > 0; });
                var last = err.length ? err[err.length - 1].trim() : "";
                root.connFailReason = last.replace(/^Error:\s*/, "").replace(/\.$/, "");
                if (!root.attemptWasKnown && root.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", root.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    /**
     * A failed `nmcli dev wifi connect` still leaves a connection profile
     * named after the SSID behind; without deleting it the network would be
     * treated as known on the next click and silently fail forever.
     */
    Process {
        id: cleanupProc
        onExited: root.refresh()
    }

    /**
     * Drops a saved profile on Forget. The list refreshes on exit so the row
     * loses its known/connected state and its lock falls back to dim.
     */
    Process {
        id: forgetProc
        onExited: root.refresh()
    }

    /**
     * Reads one saved profile's PSK on demand. The result is held only as long as
     * the row stays open; an empty result means the profile is open or stores no
     * recoverable secret, surfaced by the row as a plain note.
     */
    Process {
        id: revealProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.revealedPw = this.text.replace(/\n+$/, "");
                root.revealResolved = true;
            }
        }
    }

    onNetsChanged: if (active) secRefresh.restart()

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (root.active) secProc.running = true
    }

    /**
     * Keys the network list by SSID so a rescan diffs into the existing rows
     * rather than tearing every delegate down and rebuilding it. Delegates keep
     * their identity across scans, so the inline confirm or password row stays
     * open under the network the user tapped.
     */
    ScriptModel {
        id: netModel
        objectProp: "name"
        values: root.netsSorted
    }


    // --- inline pieces -----------------------------------------------------

    component StatCell: Item {
        property real s: 1
        property string label: ""
        property string value: ""
        property color valueColor: Theme.cream
        height: 20 * s

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 9.5 * parent.s
            font.weight: Font.Medium
        }
        Text {
            anchors.right: parent.right
            anchors.left: parent.left
            anchors.leftMargin: 62 * parent.s
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: parent.value
            color: parent.valueColor
            font.family: Theme.font
            font.pixelSize: 11 * parent.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            elide: Text.ElideMiddle
        }
    }

    Binding {
        target: NetInfo
        property: "open"
        value: root.active
    }

    Connections {
        target: NetInfo
        function onBandError(message) {
            root.bandFailMsg = message;
            bandFailClear.restart();
        }
    }
    property string bandFailMsg: ""
    Timer { id: bandFailClear; interval: 4000; onTriggered: root.bandFailMsg = "" }

    readonly property bool connected: NetInfo.iface.length > 0
    readonly property bool isWifi: NetInfo.type === "wifi"
    // The pill shows one network icon: a wired route replaces wifi, and so does this surface.
    readonly property bool wired: Radios.ethernet
    readonly property string wiredSpeed: NetInfo.linkSpeed >= 1000 ? (NetInfo.linkSpeed / 1000) + " Gbit"
        : (NetInfo.linkSpeed > 0 ? NetInfo.linkSpeed + " Mbit" : "")

    // --- header ----------------------------------------------------------

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Flags.showGlyphs
                text: root.wired ? "線" : "波"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.wired ? "ETHERNET" : "WIFI"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 128 * root.s
                text: root.wired ? "· " + (root.wiredSpeed.length ? root.wiredSpeed : "Connected") : "· " + root.statusText
                color: (root.wired || root.activeNet) ? Theme.vermLit : Theme.faint
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 13 * root.s

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.connected && root.isWifi
                width: 15 * root.s
                height: 15 * root.s
                name: "qr"
                color: root.qrOpen ? Theme.vermLit : (qrArea.containsMouse ? Theme.cream : Theme.iconDim)
                stroke: 1.7
                MouseArea {
                    id: qrArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.speedOpen = false; root.qrOpen = !root.qrOpen; }
                }
                Tooltip {
                    s: root.s
                    placement: "below"
                    align: "right"
                    title: "Share network"
                    show: qrArea.containsMouse
                }
            }

            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.connected
                width: 16 * root.s
                height: 16 * root.s
                name: "gauge"
                color: root.speedOpen ? Theme.vermLit : (speedArea.containsMouse ? Theme.cream : Theme.iconDim)
                stroke: 1.7
                MouseArea {
                    id: speedArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.qrOpen = false; root.speedOpen = !root.speedOpen; }
                }
                Tooltip {
                    s: root.s
                    placement: "below"
                    align: "right"
                    title: "Speed test"
                    show: speedArea.containsMouse
                }
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.wifiOn && !root.wired
                width: 16 * root.s
                height: 16 * root.s

                GlyphIcon {
                    id: reloadGlyph
                    anchors.fill: parent
                    name: "reboot"
                    color: root.scanning ? Theme.flameGlow : (reloadArea.containsMouse ? Theme.cream : Theme.iconDim)
                    stroke: 1.8

                    RotationAnimator {
                        target: reloadGlyph
                        running: root.scanning
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) reloadGlyph.rotation = 0
                    }
                }
                MouseArea {
                    id: reloadArea
                    anchors.fill: parent
                    anchors.margins: -6 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scanning ? root.stopScan() : root.startScan()
                }
                Tooltip {
                    s: root.s
                    placement: "below"
                    align: "right"
                    title: root.scanning ? "Scanning…" : "Rescan networks"
                    show: reloadArea.containsMouse
                }
            }

            LinkToggle {
                id: wifiToggle
                s: root.s
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.wired
                on: root.wifiOn
                onToggled: Radios.toggleWifi()

                HoverHandler { id: wifiToggleHover }
                Tooltip {
                    s: root.s
                    placement: "below"
                    align: "right"
                    title: root.wifiOn ? "Wi-Fi on" : "Wi-Fi off"
                    show: wifiToggleHover.hovered
                }
            }
        }
    }

    Rectangle {
        id: div1
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }

    // --- vitals grid ----------------------------------------------------

    Column {
        id: statGrid
        anchors.top: div1.bottom
        anchors.topMargin: root.connected ? 9 * root.s : 0
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 3 * root.s
        readonly property real cell: (width - 18 * root.s) / 2
        clip: true
        height: root.connected ? implicitHeight : 0
        opacity: root.connected ? 1 : 0
        Behavior on height { NumberAnimation { duration: Motion.fast } }

        Row {
            spacing: 18 * root.s
            StatCell { s: root.s; width: statGrid.cell; label: "Ping"; value: NetInfo.pingText }
            StatCell { s: root.s; width: statGrid.cell; label: "Packet Loss"; value: NetInfo.packetLossText }
        }
        Row {
            spacing: 18 * root.s
            StatCell { s: root.s; width: statGrid.cell; label: "Receiving"; value: NetInfo.downRateText }
            StatCell { s: root.s; width: statGrid.cell; label: "Sending"; value: NetInfo.upRateText }
        }
        Row {
            spacing: 18 * root.s
            StatCell { s: root.s; width: statGrid.cell; label: "Downloaded"; value: NetInfo.downTotalText }
            StatCell { s: root.s; width: statGrid.cell; label: "Uploaded"; value: NetInfo.upTotalText }
        }
        Row {
            spacing: 18 * root.s
            StatCell { s: root.s; width: statGrid.cell; label: "IP Address"; value: NetInfo.ipAddr }
            StatCell { s: root.s; width: statGrid.cell; label: "Gateway"; value: NetInfo.gateway }
        }
    }

    Rectangle {
        id: div2
        anchors.top: statGrid.bottom
        anchors.topMargin: root.connected ? 9 * root.s : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.connected && root.isWifi ? 1 : 0
        color: Theme.hair
    }

    // --- Wi-Fi band ---------------------------------------------------

    Column {
        id: bandSection
        anchors.top: div2.bottom
        anchors.topMargin: (root.connected && root.isWifi) ? 9 * root.s : 0
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6 * root.s
        clip: true
        height: (root.connected && root.isWifi) ? implicitHeight : 0
        opacity: (root.connected && root.isWifi) ? 1 : 0
        Behavior on height { NumberAnimation { duration: Motion.fast } }

        Item {
            width: parent.width
            height: 16 * root.s

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: NetInfo.bandTitle
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 9.5 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.4 * root.s
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AUTOMATIC"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.2 * root.s
                }
                LinkToggle {
                    s: root.s * 0.9
                    anchors.verticalCenter: parent.verticalCenter
                    on: NetInfo.bandSelected === "auto"
                    onToggled: NetInfo.setBand(NetInfo.bandSelected === "auto"
                        ? (NetInfo.band.length ? NetInfo.band : "5")
                        : "auto")

                    HoverHandler { id: autoHover }
                    Tooltip {
                        s: root.s
                        placement: "below"
                        align: "right"
                        title: NetInfo.bandSelected === "auto" ? "Automatic band" : "Band pinned"
                        desc: NetInfo.bandSelected === "auto"
                            ? "Let Wi-Fi pick 2.4 / 5 / 6 GHz"
                            : "Locked to " + NetInfo.bandSelected + " GHz"
                        show: autoHover.hovered
                    }
                }
            }
        }

        SettingsSeg {
            s: root.s
            visible: NetInfo.bandSelected !== "auto"
            options: [
                { label: "2.4", value: "2.4" },
                { label: "5", value: "5" },
                { label: "6", value: "6" }
            ].filter(function (o) { return NetInfo.bandAvailable.indexOf(o.value) >= 0 || o.value === NetInfo.band; })
            value: NetInfo.bandSelected
            onPicked: (v) => NetInfo.setBand(v)
        }

        Text {
            visible: root.bandFailMsg.length > 0
            width: parent.width
            text: root.bandFailMsg
            color: Theme.vermLit
            font.family: Theme.font
            font.pixelSize: 9 * root.s
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }

    Rectangle {
        id: div3
        anchors.top: bandSection.bottom
        anchors.topMargin: root.wired ? 0 : 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.wired ? 0 : 1
        color: Theme.hair
    }

    // --- network list --------------------------------------------------

    Item {
        id: listFrame
        anchors.top: div3.bottom
        anchors.topMargin: root.wired ? 0 : 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !root.wired
        height: root.wired ? 0 : root.wifiOn ? Math.min(Math.max(netCol.implicitHeight, 26 * root.s), 220 * root.s) : 0

        Text {
            anchors.centerIn: parent
            visible: root.wifiOn && root.nets.length === 0
            text: "Searching networks…"
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
        }

        Flickable {
            id: netFlick
            anchors.fill: parent
            contentHeight: netCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: netCol
                width: netFlick.width
                spacing: 2 * root.s

                Repeater {
                    model: netModel

                    Column {
                        id: netItem
                        required property var modelData
                        required property int index
                        readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
                        readonly property bool isActive: modelData ? modelData.connected === true : false
                        readonly property bool secured: root.isSecured(ssid)
                        readonly property bool known: root.knownProfiles[ssid] === true
                        readonly property bool expanded: ssid.length > 0 && root.expandedSsid === ssid
                        readonly property bool confirming: expanded && (isActive || known)
                        readonly property bool asking: expanded && !confirming
                        width: netCol.width
                        spacing: 2 * root.s

                        /**
                         * Section header shown above this row: "KNOWN NETWORKS" at
                         * the top of the saved block, "OTHER NETWORKS" at the first
                         * unsaved row. netsSorted groups connected → known → signal
                         * so the two blocks are contiguous.
                         */
                        readonly property bool inKnown: netItem.isActive || netItem.known
                        readonly property string section: {
                            var rows = root.netsSorted;
                            if (netItem.index === 0)
                                return netItem.inKnown ? "KNOWN NETWORKS" : "OTHER NETWORKS";
                            var prev = rows[netItem.index - 1];
                            var prevKnown = prev && (prev.connected === true || root.knownProfiles[prev.name] === true);
                            return (prevKnown && !netItem.inKnown) ? "OTHER NETWORKS" : "";
                        }

                        Text {
                            visible: netItem.section.length > 0
                            height: visible ? 20 * root.s : 0
                            leftPadding: 10 * root.s
                            topPadding: netItem.index === 0 ? 0 : 8 * root.s
                            verticalAlignment: Text.AlignBottom
                            text: netItem.section
                            color: Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: 9 * root.s
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.4 * root.s
                        }

                        function syncPwField() {
                            pwField.text = root.pwDraft;
                            pwField.cursorPosition = pwField.text.length;
                            pwField.forceActiveFocus();
                        }

                        onExpandedChanged: if (asking) Qt.callLater(syncPwField)
                        Component.onCompleted: if (asking) Qt.callLater(syncPwField)

                        Rectangle {
                            width: parent.width
                            height: 30 * root.s
                            radius: 9 * root.s
                            color: netItem.isActive ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.14)
                                : (rowHover.hovered ? Theme.frameBg : "transparent")

                            HoverHandler { id: rowHover }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activateNetwork(netItem.modelData)
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: rowRight.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: netItem.ssid.length ? netItem.ssid : "Hidden"
                                color: netItem.isActive ? Theme.vermLit : Theme.subtle
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: netItem.isActive ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7 * root.s

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.connecting && root.attemptSsid === netItem.ssid
                                    width: 4 * root.s
                                    height: 4 * root.s
                                    radius: width / 2
                                    color: Theme.flameGlow

                                    SequentialAnimation on opacity {
                                        running: root.connecting && root.attemptSsid === netItem.ssid
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                    }
                                }

                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -1.4 * root.s
                                    visible: netItem.secured
                                    width: 14 * root.s
                                    height: 14 * root.s

                                    GlyphIcon {
                                        anchors.fill: parent
                                        name: "lock-outline"
                                        color: netItem.isActive ? Theme.vermLit : Theme.iconDim
                                        stroke: 1.9
                                    }
                                }

                                WifiGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 15 * root.s
                                    height: 15 * root.s
                                    s: root.s
                                    on: true
                                    level: (netItem.modelData && netItem.modelData.signalStrength) || 0
                                }
                            }
                        }

                        Text {
                            visible: netItem.isActive && root.connDetail.length > 0
                            width: parent.width
                            text: root.connDetail
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Medium
                            leftPadding: 10 * root.s
                            bottomPadding: 2 * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        Item {
                            visible: netItem.confirming
                            width: parent.width
                            height: 30 * root.s

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: confirmBtns.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: netItem.isActive ? "Connected" : "Saved network"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9.5 * root.s
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }

                            Row {
                                id: confirmBtns
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6 * root.s

                                Rectangle {
                                    id: primaryBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: primaryLabel.implicitWidth + 20 * root.s
                                    height: 22 * root.s
                                    radius: 7 * root.s
                                    color: primaryArea.containsMouse ? Theme.tileBg : "transparent"
                                    border.width: 1
                                    border.color: primaryArea.containsMouse ? Theme.vermDim : Theme.border

                                    Text {
                                        id: primaryLabel
                                        anchors.centerIn: parent
                                        text: netItem.isActive ? "Disconnect" : "Connect"
                                        color: Theme.cream
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.3 * root.s
                                    }

                                    MouseArea {
                                        id: primaryArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: netItem.isActive
                                            ? root.disconnectNetwork(netItem.modelData)
                                            : root.connectKnown(netItem.modelData)
                                    }
                                }

                                Rectangle {
                                    id: revealBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: netItem.known
                                    readonly property bool shown: root.revealedSsid === netItem.ssid
                                    width: revealLabel.implicitWidth + 20 * root.s
                                    height: 22 * root.s
                                    radius: 7 * root.s
                                    color: revealArea.containsMouse ? Theme.tileBg : "transparent"
                                    border.width: 1
                                    border.color: revealBtn.shown
                                        ? Theme.vermDim
                                        : (revealArea.containsMouse ? Theme.vermDim : Theme.border)

                                    Text {
                                        id: revealLabel
                                        anchors.centerIn: parent
                                        text: revealBtn.shown ? "Hide" : "Show"
                                        color: Theme.cream
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.3 * root.s
                                    }

                                    MouseArea {
                                        id: revealArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.revealPassword(netItem.ssid)
                                    }
                                }

                                Rectangle {
                                    id: forgetBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: forgetLabel.implicitWidth + 20 * root.s
                                    height: 22 * root.s
                                    radius: 7 * root.s
                                    color: forgetArea.containsMouse
                                        ? Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.2)
                                        : Qt.rgba(Theme.verm.r, Theme.verm.g, Theme.verm.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.vermLit.r, Theme.vermLit.g, Theme.vermLit.b, 0.45)

                                    Text {
                                        id: forgetLabel
                                        anchors.centerIn: parent
                                        text: "Forget"
                                        color: Theme.vermLit
                                        font.family: Theme.font
                                        font.pixelSize: 10 * root.s
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.3 * root.s
                                    }

                                    MouseArea {
                                        id: forgetArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.forgetNetwork(netItem.ssid)
                                    }
                                }
                            }
                        }

                        Item {
                            readonly property bool shown: netItem.confirming && root.revealedSsid === netItem.ssid
                            visible: shown
                            width: parent.width
                            height: shown ? 24 * root.s : 0

                            Text {
                                id: revealCaption
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: "PASSWORD"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 9 * root.s
                                font.weight: Font.Medium
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 1 * root.s
                            }

                            Text {
                                visible: root.revealResolved && root.revealedPw.length === 0
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                text: "no saved password"
                                color: Theme.faint
                                font.family: Theme.font
                                font.pixelSize: 10 * root.s
                                font.weight: Font.Medium
                            }

                            TextEdit {
                                visible: root.revealedPw.length > 0
                                anchors.left: revealCaption.right
                                anchors.leftMargin: 10 * root.s
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: TextEdit.AlignRight
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Theme.verm
                                wrapMode: TextEdit.NoWrap
                                clip: true
                                text: root.revealedSsid === netItem.ssid ? root.revealedPw : ""
                                color: Theme.flameCore
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                font.weight: Font.Medium
                            }
                        }

                        Item {
                            visible: netItem.asking
                            width: parent.width
                            height: 30 * root.s

                            TextField {
                                id: pwField
                                anchors.left: parent.left
                                anchors.leftMargin: 10 * root.s
                                anchors.right: pwRight.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                background: null
                                padding: 0
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                                echoMode: TextInput.Password
                                placeholderText: "Password"
                                placeholderTextColor: Theme.faint
                                selectByMouse: true
                                selectionColor: Theme.verm
                                onTextEdited: root.pwDraft = text
                                onAccepted: root.connectWithPassword(netItem.ssid, text)
                            }

                            Row {
                                id: pwRight
                                anchors.right: parent.right
                                anchors.rightMargin: 10 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 7 * root.s

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.connecting && netItem.asking
                                    width: 4 * root.s
                                    height: 4 * root.s
                                    radius: width / 2
                                    color: Theme.flameGlow

                                    SequentialAnimation on opacity {
                                        running: root.connecting && netItem.asking
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: Motion.pulse; easing.type: Easing.InOutSine }
                                    }
                                }

                                GlyphIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14 * root.s
                                    height: 14 * root.s
                                    name: "return"
                                    color: enterArea.containsMouse ? Theme.cream : Theme.vermLit
                                    stroke: 1.8

                                    MouseArea {
                                        id: enterArea
                                        anchors.fill: parent
                                        anchors.margins: -6 * root.s
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.connectWithPassword(netItem.ssid, pwField.text)
                                    }
                                }
                            }
                        }

                        Text {
                            visible: netItem.asking && root.connectFailed
                            width: parent.width
                            text: "Connection failed" + (root.connFailReason.length ? " · " + root.connFailReason : "")
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 9.5 * root.s
                            leftPadding: 10 * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }
        }

        WheelScroller {
            anchors.fill: parent
            s: root.s
            flick: netFlick
        }
    }

    // --- overlays (QR share, speed test) --------------------------------

    property bool qrOpen: false
    property bool speedOpen: false

    WifiQr {
        anchors.fill: parent
        s: root.s
        open: root.qrOpen
        onRequestClose: root.qrOpen = false
    }

    WifiSpeedTest {
        anchors.fill: parent
        s: root.s
        open: root.speedOpen
        onRequestClose: root.speedOpen = false
    }
}
