import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const G = require("./gcal.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) { eq(!!cond, true, msg); }

const timed = { id: "a#1", account: "a@b.com", calendar: "Work",
    date: "2026-09-08", endDate: "", time: "09:00", endTime: "10:00", text: "Standup" };
const allday = { id: "a#2", account: "a@b.com", calendar: "Personal",
    date: "2026-09-08", endDate: "", time: "", endTime: "", text: "Holiday" };
const span = { id: "a#3", account: "a@b.com", calendar: "Trips",
    date: "2026-09-07", endDate: "2026-09-10", time: "", endTime: "", text: "Lisbon" };

// --- covers --------------------------------------------------------------
ok(G.covers(timed, "2026-09-08"), "timed covers its own day");
ok(!G.covers(timed, "2026-09-09"), "timed does not cover the next day");
ok(G.covers(span, "2026-09-07"), "span covers its first day");
ok(G.covers(span, "2026-09-09"), "span covers an interior day");
ok(G.covers(span, "2026-09-10"), "span covers its last day (inclusive)");
ok(!G.covers(span, "2026-09-11"), "span stops after endDate");
ok(!G.covers(span, "2026-09-06"), "span starts at date");

// --- byStartTime ----------------------------------------------------
eq([timed, allday].slice().sort(G.byStartTime).map(e => e.id), ["a#2", "a#1"],
    "byStartTime floats the all-day (empty time) ahead of the timed one");

// --- forDate sort ------------------------------------------------------
const day = G.forDate([timed, allday, span], "2026-09-08");
eq(day.map(e => e.id), ["a#2", "a#3", "a#1"], "all-day and span (empty time) sort before timed");
eq(G.forDate([timed, allday, span], "2026-09-09").map(e => e.id), ["a#3"], "only the span reaches 09-09");
eq(G.forDate([], "2026-09-08"), [], "empty input is empty");

// --- hasEvents --------------------------------------------------------
ok(G.hasEvents([span], "2026-09-09"), "hasEvents true inside a span");
ok(!G.hasEvents([timed], "2026-09-01"), "hasEvents false on an empty day");

// --- meta ------------------------------------------------------------
eq(G.meta(timed), "09:00–10:00 · Work", "timed meta: range + calendar");
eq(G.meta(allday), "all day · Personal", "all-day meta");
eq(G.meta({ ...timed, endTime: "" }), "09:00 · Work", "open-ended timed meta drops the dash");
eq(G.meta(span, (lo, hi) => lo + "→" + hi),
    "2026-09-07→2026-09-10 · all day · Trips", "span meta prepends the formatted range");

if (failed) { console.log("\n" + failed + " FAILED"); process.exit(1); }
console.log("\nall passed");
