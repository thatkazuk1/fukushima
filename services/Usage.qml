pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LLM usage limits for the pill. The `llm-usage` collector (a separate tool)
 * writes one JSON file atomically every minute; this singleton only watches and
 * reads that file. It never reads provider credentials and never polls the
 * file: FileView reloads on change. A 30 second tick only refreshes the
 * countdown and age labels.
 *
 * File: `$XDG_STATE_HOME/llm-usage/usage.json`, contract version 1. A provider
 * has `status` ok, stale, unavailable or error, an optional `plan` and
 * `reason`, and `windows` keyed `session` (5 hours) and `weekly` (7 days).
 * Antigravity has no session window: it sends `weekly` and `weekly_3p`. A
 * window can carry its own `label` and `short` names.
 * Times are Unix epoch seconds and `used_percent` is 0 to 100. A missing
 * window or provider is shown dim with a reason, never as an error.
 *
 * Warnings fire once at 80, 95 and 100 percent for each window. The first read
 * after a shell start only sets the latches, so a shell reload at 90 percent
 * does not repeat a warning that already fired. A latch re-arms when the window
 * resets or the percent falls below the level.
 *
 * A lazy singleton: `void Usage.armed` from the shell's Component.onCompleted
 * starts the watcher.
 */
Singleton {
    id: root

    readonly property bool armed: true

    readonly property var order: ["codex", "claude", "antigravity"]
    readonly property var names: ({ codex: "Codex", claude: "Claude", antigravity: "Antigravity" })
    readonly property var windowNames: ({ session: "5h session", weekly: "7d weekly" })
    readonly property var windowShort: ({ session: "5h", weekly: "7d" })
    readonly property var levels: [80, 95, 100]
    readonly property int staleSecs: 600

    /** Provider rows for the UI: id, name, status, plan, reason, updatedAt, windows. */
    property var providers: []
    property real fileUpdatedAt: 0
    property bool loaded: false
    property int tick: 0

    /** True when at least one provider reports a window, so the face has data to show. */
    readonly property bool hasData: {
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].windows.length > 0)
                return true;
        }
        return false;
    }

    /** Highest used percent over every window of every provider with data, or -1. */
    readonly property real peak: {
        var m = -1;
        for (var i = 0; i < providers.length; i++)
            m = Math.max(m, peakOf(providers[i]));
        return m;
    }

    function peakOf(p) {
        var m = -1;
        for (var j = 0; j < p.windows.length; j++)
            m = Math.max(m, p.windows[j].pct);
        return m;
    }

    /**
     * Effective status. The collector sets "stale" for each provider with its
     * own age limit. This adds only one case: the whole file is old, so the
     * collector stopped and an "ok" status can no longer be trusted.
     */
    function statusOf(p) {
        void root.tick;
        if (p.status === "ok" && fileUpdatedAt > 0
                && (Date.now() / 1000 - fileUpdatedAt) > staleSecs)
            return "stale";
        return p.status;
    }

    function resetIn(ts) {
        void root.tick;
        if (!ts || ts <= 0)
            return "";
        var s = Math.round(ts - Date.now() / 1000);
        if (s <= 0)
            return "reset due";
        var d = Math.floor(s / 86400);
        var h = Math.floor((s % 86400) / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (d > 0)
            return "resets in " + d + "d " + h + "h";
        if (h > 0)
            return "resets in " + h + "h " + m + "m";
        return "resets in " + Math.max(1, m) + "m";
    }

    /** Compact countdown for the ring cards, for example "4h 59m". */
    function resetShort(ts) {
        void root.tick;
        if (!ts || ts <= 0)
            return "";
        var s = Math.round(ts - Date.now() / 1000);
        if (s <= 0)
            return "due";
        var d = Math.floor(s / 86400);
        var h = Math.floor((s % 86400) / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (d > 0)
            return d + "d " + h + "h";
        if (h > 0)
            return h + "h " + m + "m";
        return Math.max(1, m) + "m";
    }

    /** Window to draw on the outer ring (weekly, else the first one). */
    function outerWindow(p) {
        for (var i = 0; i < p.windows.length; i++) {
            if (p.windows[i].key === "weekly")
                return p.windows[i];
        }
        return p.windows.length > 0 ? p.windows[0] : null;
    }

    /**
     * Window to draw on the inner ring: the session, else the first window that
     * is not on the outer ring. Null when the provider has only one window.
     */
    function innerWindow(p) {
        var outer = outerWindow(p);
        var other = null;
        for (var i = 0; i < p.windows.length; i++) {
            var w = p.windows[i];
            if (w === outer)
                continue;
            if (w.key === "session")
                return w;
            if (other === null)
                other = w;
        }
        return other;
    }

    function ageOf(ts) {
        void root.tick;
        if (!ts || ts <= 0)
            return "";
        var s = Math.max(0, Math.round(Date.now() / 1000 - ts));
        if (s < 60)
            return "just now";
        var m = Math.floor(s / 60);
        if (m < 60)
            return m + "m ago";
        var h = Math.floor(m / 60);
        return h < 24 ? h + "h ago" : Math.floor(h / 24) + "d ago";
    }

    function emptyProvider(id, reason) {
        return { id: id, name: names[id] || id, status: "unavailable", plan: "",
                 reason: reason, updatedAt: 0, windows: [] };
    }

    function buildProvider(id, raw) {
        var wins = [];
        var w = raw.windows || {};
        var keys = Object.keys(w).sort(function(a, b) {
            var o = { session: 0, weekly: 1, weekly_3p: 2 };
            return (o[a] !== undefined ? o[a] : 9) - (o[b] !== undefined ? o[b] : 9);
        });
        for (var i = 0; i < keys.length; i++) {
            var it = w[keys[i]];
            if (!it || typeof it.used_percent !== "number")
                continue;
            wins.push({ key: keys[i], label: String(it.label || windowNames[keys[i]] || keys[i]),
                        short: String(it.short || windowShort[keys[i]] || keys[i]),
                        pct: Math.max(0, Math.min(100, it.used_percent)),
                        resetsAt: Number(it.resets_at) || 0 });
        }
        var status = String(raw.status || "unavailable");
        var reason = String(raw.reason || "");
        if (status !== "ok" && status !== "stale" && status !== "unavailable" && status !== "error")
            status = "error";
        if (reason.length === 0 && status === "unavailable")
            reason = "no data yet";
        return { id: id, name: names[id] || id, status: status, plan: String(raw.plan || ""),
                 reason: reason, updatedAt: Number(raw.updated_at) || 0, windows: wins };
    }

    function parse(text) {
        var rows = [];
        var doc = null;
        if (text && text.length > 0) {
            try { doc = JSON.parse(text); } catch (e) { doc = null; }
        }
        var reasonMissing = doc === null
            ? (text && text.length > 0 ? "usage file is unreadable" : "collector has not written data yet")
            : "collector reports no data";
        var provs = (doc && doc.providers) ? doc.providers : {};
        var ids = order.slice();
        Object.keys(provs).forEach(function(k) { if (ids.indexOf(k) < 0) ids.push(k); });
        for (var i = 0; i < ids.length; i++) {
            rows.push(provs[ids[i]] ? buildProvider(ids[i], provs[ids[i]])
                                    : emptyProvider(ids[i], reasonMissing));
        }
        root.fileUpdatedAt = doc ? (Number(doc.updated_at) || 0) : 0;
        root.providers = rows;
        root.checkAlerts(rows);
        root.loaded = true;
    }

    // Warning latches: key -> { level, resetsAt }.
    property var latches: ({})
    property bool baselined: false
    property var queue: []

    function levelFor(pct) {
        var l = 0;
        for (var i = 0; i < levels.length; i++) {
            if (pct >= levels[i])
                l = levels[i];
        }
        return l;
    }

    function checkAlerts(rows) {
        var next = {};
        for (var i = 0; i < rows.length; i++) {
            var p = rows[i];
            if (p.status !== "ok")
                continue;
            for (var j = 0; j < p.windows.length; j++) {
                var w = p.windows[j];
                var key = p.id + ":" + w.key;
                var lvl = levelFor(w.pct);
                var prev = latches[key];
                var prevLvl = (prev && prev.resetsAt === w.resetsAt) ? prev.level : 0;
                if (baselined && lvl > prevLvl) {
                    queue.push({ urgency: lvl >= 95 ? "critical" : "normal",
                                 summary: p.name + " " + w.label + " limit at " + Math.round(w.pct) + "%",
                                 body: lvl >= 100 ? "The limit is reached. " + resetIn(w.resetsAt) + "."
                                                  : resetIn(w.resetsAt) + "." });
                }
                next[key] = { level: lvl, resetsAt: w.resetsAt };
            }
        }
        // A window the file no longer lists keeps its old latch, so a short
        // outage does not repeat a warning that already fired.
        Object.keys(latches).forEach(function(k) { if (!next[k]) next[k] = latches[k]; });
        latches = next;
        baselined = true;
        if (queue.length > 0 && !drain.running)
            drain.start();
    }

    Timer {
        id: drain
        interval: 400
        repeat: true
        onTriggered: {
            if (root.queue.length === 0) {
                stop();
                return;
            }
            var n = root.queue.shift();
            noteProc.command = ["notify-send", "-a", "Fukushima", "-u", n.urgency, n.summary, n.body];
            noteProc.running = true;
        }
    }

    Process { id: noteProc }

    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: root.tick += 1
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
            + "/llm-usage/usage.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(file.text())
        onLoadFailed: root.parse("")
    }
}
