/**
 * Pure helpers for the network panel: throughput deltas, a rolling ping window,
 * and the byte / rate / latency formatting. No QML, no I/O — the Network
 * service feeds it raw `/sys/class/net` counters and `ping` results and reads
 * back display strings. Kept testable so the arithmetic is exercised without a
 * compositor (see net.test.mjs).
 */

/**
 * Two-sample throughput. `sample` carries the current cumulative rx/tx byte
 * counters (as read straight from /sys/class/net/<iface>/statistics) and the
 * interface name; `now` is a seconds timestamp. A changed interface or the
 * first call seeds without emitting a rate. `downTotal` / `upTotal` are just
 * those cumulative counters — "downloaded / uploaded since this link came up".
 */
function throughput(prev, sample, now) {
    var p = prev || {};
    var iface = sample.iface || "";
    var rx = Number(sample.rx) || 0;
    var tx = Number(sample.tx) || 0;

    if (iface !== (p.iface || "") || !p.at) {
        return {
            iface: iface, rx: rx, tx: tx, at: now,
            downRate: 0, upRate: 0, downTotal: rx, upTotal: tx
        };
    }

    var dt = now - p.at;
    var downRate = p.downRate || 0;
    var upRate = p.upRate || 0;
    if (dt > 0) {
        downRate = Math.max(0, (rx - p.rx) / dt);
        upRate = Math.max(0, (tx - p.tx) / dt);
    }

    return {
        iface: iface, rx: rx, tx: tx, at: now,
        downRate: downRate, upRate: upRate,
        downTotal: rx, upTotal: tx
    };
}

/** Append a ping result (a number in ms, or null for a timeout) and cap the window. */
function pingPush(samples, value, limit) {
    var out = Array.isArray(samples) ? samples.slice() : [];
    out.push(typeof value === "number" && isFinite(value) && value >= 0 ? value : null);
    while (out.length > (limit || 5))
        out.shift();
    return out;
}

/** Mean of the non-timeout samples, or -1 when the window holds none. */
function pingAvg(samples) {
    var v = Array.isArray(samples) ? samples : [];
    var total = 0, n = 0;
    for (var i = 0; i < v.length; i++) {
        if (typeof v[i] === "number") { total += v[i]; n++; }
    }
    return n > 0 ? total / n : -1;
}

/** Percentage of the window that timed out. Empty window = 0. */
function pingLoss(samples) {
    var v = Array.isArray(samples) ? samples : [];
    if (v.length === 0)
        return 0;
    var lost = 0;
    for (var i = 0; i < v.length; i++)
        if (v[i] === null) lost++;
    return Math.round((lost / v.length) * 100);
}

function fmtBytes(n) {
    var x = Number(n);
    if (!isFinite(x) || x < 0) x = 0;
    if (x < 1024) return Math.round(x) + " B";
    if (x < 1048576) return (x / 1024).toFixed(1) + " KB";
    if (x < 1073741824) return (x / 1048576).toFixed(1) + " MB";
    return (x / 1073741824).toFixed(2) + " GB";
}

function fmtRate(bytesPerSec) {
    return fmtBytes(bytesPerSec) + "/s";
}

/**
 * `hasSamples` false = no probe has returned yet (show "--", don't reflow the
 * grid a second after open); a resolved timeout reads "Timeout".
 */
function fmtPing(ms, hasSamples) {
    if (hasSamples === false)
        return "--";
    var v = parseFloat(ms);
    if (!isFinite(v) || v < 0)
        return "Timeout";
    return v.toFixed(v > 0 && v < 10 ? 1 : 0) + " ms";
}

function fmtLoss(pct, hasSamples) {
    if (hasSamples === false)
        return "--";
    var v = parseInt(pct, 10);
    return (!v || v < 0) ? "0%" : v + "%";
}

/** Wi-Fi frequency in MHz to a band key. "" when it falls outside the known bands. */
function bandForFreq(mhz) {
    var v = parseFloat(mhz);
    if (!isFinite(v)) return "";
    if (v >= 2400 && v < 2500) return "2.4";
    if (v >= 4900 && v < 5925) return "5";
    if (v >= 5925 && v < 7125) return "6";
    return "";
}

function bandLabel(band) {
    if (band === "auto") return "Auto";
    if (!band) return "";
    return band + "GHz";
}

/**
 * Under Automatic the band pills are hidden, so the section header carries the
 * live band — "WI-FI BAND: 5GHZ". Once a band is pinned the pills show it
 * themselves and the header drops back to a plain label. Mirrors omarchy's
 * behaviour so the two never disagree.
 */
function bandSectionTitle(selected, current) {
    if (selected && selected !== "auto")
        return "WI-FI BAND";
    var label = bandLabel(current);
    return label ? "WI-FI BAND: " + label.toUpperCase() : "WI-FI BAND";
}

/** `WIFI:` payload for a QR, with the reserved characters escaped per the spec. */
function wifiQrPayload(ssid, security, password, hidden) {
    function esc(v) {
        return String(v || "").replace(/([\\;,:"])/g, "\\$1");
    }
    var p = "WIFI:T:" + (security || "nopass") + ";S:" + esc(ssid) + ";";
    if (security && security !== "nopass")
        p += "P:" + esc(password) + ";";
    if (hidden)
        p += "H:true;";
    return p + ";";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        throughput: throughput,
        pingPush: pingPush,
        pingAvg: pingAvg,
        pingLoss: pingLoss,
        fmtBytes: fmtBytes,
        fmtRate: fmtRate,
        fmtPing: fmtPing,
        fmtLoss: fmtLoss,
        bandForFreq: bandForFreq,
        bandLabel: bandLabel,
        bandSectionTitle: bandSectionTitle,
        wifiQrPayload: wifiQrPayload
    };
}
