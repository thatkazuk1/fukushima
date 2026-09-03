import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const N = require("./net.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) { eq(!!cond, true, msg); }

// --- throughput -----------------------------------------------------------
let t = N.throughput(null, { iface: "wlo1", rx: 1000, tx: 500 }, 100);
eq(t.downRate, 0, "first sample seeds, no rate");
eq(t.baseRx, 1000, "base rx captured on seed");

t = N.throughput(t, { iface: "wlo1", rx: 3000, tx: 700 }, 102);
eq(t.downRate, 1000, "down rate = (3000-1000)/2s");
eq(t.upRate, 100, "up rate = (700-500)/2s");
eq(t.downTotal, 2000, "session down total from base");
eq(t.upTotal, 200, "session up total from base");

let t2 = N.throughput(t, { iface: "eth0", rx: 10, tx: 10 }, 103);
eq(t2.downRate, 0, "iface change reseeds");
eq(t2.baseRx, 10, "iface change rebases");

let t3 = N.throughput(t, { iface: "wlo1", rx: 2000, tx: 700 }, 104);
eq(t3.downRate, 0, "counter reset clamps to 0, not negative");

// --- ping window --------------------------------------------------------
let w = [];
w = N.pingPush(w, 10, 5);
w = N.pingPush(w, 12, 5);
w = N.pingPush(w, null, 5);
w = N.pingPush(w, 8, 5);
eq(w, [10, 12, null, 8], "window keeps order incl timeout");
eq(N.pingAvg(w), 10, "avg ignores the timeout: (10+12+8)/3");
eq(N.pingLoss(w), 25, "loss = 1/4");

for (let i = 0; i < 10; i++) w = N.pingPush(w, 5, 5);
eq(w.length, 5, "window capped at limit");
eq(N.pingLoss([]), 0, "empty window is 0% loss");
eq(N.pingAvg([null, null]), -1, "all-timeout window averages -1");

// --- formatting --------------------------------------------------------
eq(N.fmtBytes(0), "0 B", "zero bytes");
eq(N.fmtBytes(512), "512 B", "sub-KB");
eq(N.fmtBytes(963142), "940.6 KB", "KB");
eq(N.fmtBytes(1024 * 1024 * 128.41), "128.4 MB", "MB");
eq(N.fmtBytes(1073741824 * 128.41), "128.41 GB", "GB two decimals");
eq(N.fmtRate(963142), "940.6 KB/s", "rate suffix");
eq(N.fmtPing(10, true), "10 ms", "ping whole ms");
eq(N.fmtPing(3.35, true), "3.4 ms", "ping < 10 keeps one decimal");
eq(N.fmtPing(-1, true), "Timeout", "negative ping = Timeout");
eq(N.fmtPing(0, false), "--", "no samples yet = --");
eq(N.fmtLoss(0, true), "0%", "zero loss");
eq(N.fmtLoss(25, true), "25%", "loss pct");
eq(N.fmtLoss(0, false), "--", "loss no samples = --");

// --- band --------------------------------------------------------------
eq(N.bandForFreq(2412), "2.4", "2.4GHz channel 1");
eq(N.bandForFreq(5745), "5", "5GHz");
eq(N.bandForFreq(6135), "6", "6GHz");
eq(N.bandForFreq(999), "", "out of band");
eq(N.bandLabel("auto"), "Auto", "auto label");
eq(N.bandLabel("5"), "5GHz", "band label");
eq(N.bandSectionTitle("auto", "5"), "WI-FI BAND: 5GHZ", "auto header carries live band");
eq(N.bandSectionTitle("5", "5"), "WI-FI BAND", "pinned header is plain");

// --- qr payload ------------------------------------------------------
eq(N.wifiQrPayload("Cinque", "WPA", "s3cr;et", false),
   "WIFI:T:WPA;S:Cinque;P:s3cr\\;et;;", "qr escapes the semicolon");
eq(N.wifiQrPayload("Open Net", "nopass", "", false),
   "WIFI:T:nopass;S:Open Net;;", "open network omits password");

process.exit(failed === 0 ? 0 : 1);
