/**
 * Pure helpers for Google Calendar events in the calendar surface. No QML, no
 * I/O — services/Gcal.qml hands these the already-normalised array that
 * scripts/gcal.py emits (concrete zero-padded "YYYY-MM-DD" dates, "HH:MM" or
 * "" times) and reads back coverage tests and the editor's meta line.
 *
 * The event shape matches services/Events.qml's one-off entries exactly —
 * { id, date, endDate, time, endTime, text } — plus { account, calendar } for
 * the read-only badge. There is no recurrence field: the API expands recurring
 * events into concrete instances before we ever see them, so covers() is a
 * plain span compare with no "MM-DD" tail matching. Kept testable so the date
 * arithmetic runs without a compositor (see gcal.test.mjs).
 */

/** Last day an event covers: its endDate, or its start when single-day. */
function lastDay(e) {
    return e.endDate && e.endDate.length > 0 ? e.endDate : e.date;
}

/** True when `dateStr` ("YYYY-MM-DD") falls within the event's span, inclusive. */
function covers(e, dateStr) {
    return dateStr >= e.date && dateStr <= lastDay(e);
}

/**
 * Order comparator matching services/Events.qml's forDate(): by start time,
 * with an empty (all-day) time first. Exposed so a merged local + Google day
 * list can be re-sorted into one consistent order.
 */
function byStartTime(a, b) {
    var at = a.time || "";
    var bt = b.time || "";
    if (at === bt)
        return 0;
    if (at === "")
        return -1;
    if (bt === "")
        return 1;
    return at < bt ? -1 : 1;
}

/** Events covering `dateStr`, sorted by {@link byStartTime}. */
function forDate(events, dateStr) {
    var out = (events || []).filter(function (e) { return covers(e, dateStr); });
    out.sort(byStartTime);
    return out;
}

function hasEvents(events, dateStr) {
    for (var i = 0; i < (events || []).length; i++) {
        if (covers(events[i], dateStr))
            return true;
    }
    return false;
}

/**
 * The editor row's second line for a Google event: a date span when multi-day,
 * then "all day" or "09:00–10:00", then the calendar name so three accounts'
 * entries stay tellable apart. `fmtSpan(loKey, hiKey)` is passed in from
 * Calendar.qml (its locale-aware "22–25 Jun" formatter) to keep one source.
 */
function meta(e, fmtSpan) {
    var parts = [];
    if (e.endDate && e.endDate.length > 0 && typeof fmtSpan === "function")
        parts.push(fmtSpan(e.date, e.endDate));
    var t = e.time || "";
    var end = e.endTime || "";
    parts.push(t.length === 0 ? "all day" : (end.length > 0 ? t + "–" + end : t));
    if (e.calendar && e.calendar.length > 0)
        parts.push(e.calendar);
    return parts.join(" · ");
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        lastDay: lastDay,
        covers: covers,
        byStartTime: byStartTime,
        forDate: forDate,
        hasEvents: hasEvents,
        meta: meta
    };
}
