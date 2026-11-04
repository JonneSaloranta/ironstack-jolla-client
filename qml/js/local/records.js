.pragma library
.import "db.js" as Db
.import "http.js" as Http

// Personal records - IronStack's apps/records/services.py. Every record
// comes from replaying an exercise's eligible sets (no warm-ups, no
// failed sets) in the order they were logged, with the server's strict
// "beats" comparisons, the way its rebuild_records does after an edit.
// A new set is the same replay: whatever it adds is its new_records.

var REP_MILESTONES = [1, 3, 5, 8, 10, 12]

function label(type) {
    switch (type) {
    case "max_weight": return qsTranslate("Records", "Max weight")
    case "rep_pr": return qsTranslate("Records", "Rep PR")
    case "rep_specific_pr": return qsTranslate("Records", "Rep-specific PR")
    case "estimated_1rm": return qsTranslate("Records", "Estimated 1RM")
    case "set_volume": return qsTranslate("Records", "Set volume")
    case "session_volume": return qsTranslate("Records", "Session volume")
    }
    return type
}

// Epley, rounded to two places like apps/records/one_rep_max.py.
function estimate(weight, reps) {
    return Math.round(weight * (1 + reps / 30) * 100) / 100
}

function beats(value, previous) {
    return previous === null || previous === undefined || value > previous + 1e-9
}

function key(type, setId, repCount, sessionId) {
    return type === "session_volume" ? "session:" + sessionId : setId + ":" + type + ":" + (repCount || "")
}

// The records the exercise's history makes, by key, each with the value
// it beat (previous_value) for a PR notification.
function replay(tx, exerciseId) {
    var rows = tx.executeSql("SELECT id, weight, reps, performed_at, session FROM sets WHERE exercise = ? "
                             + "AND is_warmup = 0 AND is_failure = 0 ORDER BY performed_at, id", [exerciseId]).rows
    var desired = {}
    var maxWeight = null, bestEstimate = null, bestVolume = null
    var bestRepsAt = {}, bestWeightFor = {}, sessionTotals = {}
    // The two highest session totals (different sessions), kept as they
    // grow - a session's total only ever goes up during the replay.
    var top = {
        id: null, value: null, secondId: null, second: null,
        update: function(session, total) {
            if (this.id === session) {
                this.value = total
            } else if (this.secondId === session) {
                this.second = total
                if (total > this.value) {
                    this.secondId = this.id; this.second = this.value
                    this.id = session; this.value = total
                }
            } else if (this.value === null || total > this.value) {
                this.secondId = this.id; this.second = this.value
                this.id = session; this.value = total
            } else if (this.second === null || total > this.second) {
                this.secondId = session; this.second = total
            }
        }
    }

    function add(type, s, value, previous, repCount) {
        desired[key(type, s.id, repCount, s.session)] = {
            record_type: type, rep_count: repCount || null, value: value, previous_value: previous,
            weight: s.weight, reps: s.reps, set_id: s.id, session: s.session, achieved_at: s.performed_at
        }
    }

    for (var i = 0; i < rows.length; i++) {
        var s = rows.item(i)
        var weight = s.weight, reps = s.reps
        if (beats(weight, maxWeight)) {
            add("max_weight", s, weight, maxWeight)
            maxWeight = weight
        }
        var atWeight = bestRepsAt[weight.toFixed(2)]
        if (beats(reps, atWeight === undefined ? null : atWeight)) {
            add("rep_pr", s, reps, atWeight === undefined ? null : atWeight)
            bestRepsAt[weight.toFixed(2)] = reps
        }
        REP_MILESTONES.forEach(function(milestone) {
            var previous = bestWeightFor[milestone]
            if (reps >= milestone && beats(weight, previous === undefined ? null : previous)) {
                add("rep_specific_pr", s, weight, previous === undefined ? null : previous, milestone)
                bestWeightFor[milestone] = weight
            }
        })
        var e = reps >= 1 ? estimate(weight, reps) : 0
        if (reps >= 1 && beats(e, bestEstimate)) {
            add("estimated_1rm", s, e, bestEstimate)
            bestEstimate = e
        }
        var volume = weight * reps
        if (beats(volume, bestVolume)) {
            add("set_volume", s, volume, bestVolume)
            bestVolume = volume
        }
        var total = (sessionTotals[s.session] || 0) + volume
        sessionTotals[s.session] = total
        var bestOther = top.id === s.session ? top.second : top.value
        if (beats(total, bestOther))
            add("session_volume", s, total, bestOther)
        top.update(s.session, total)
    }
    return desired
}

function storedKey(row) {
    return key(row.record_type, row.set_id, row.rep_count, row.session)
}

function putRecord(tx, id, exerciseId, r) {
    var data = { id: id, exercise: exerciseId, record_type: r.record_type, rep_count: r.rep_count,
                 value: r.value, weight: r.weight, reps: r.reps, achieved_at: r.achieved_at }
    Db.put(tx, "records", data, { exercise: exerciseId, record_type: r.record_type, rep_count: r.rep_count,
                                  value: r.value, set_id: r.set_id, session: r.session, achieved_at: r.achieved_at })
}

// Brings the exercise's stored records in line with its history.
// Returns the records it added (with previous_value), unsorted.
function rebuild(tx, exerciseId) {
    var desired = replay(tx, exerciseId)
    var stored = tx.executeSql("SELECT id, record_type, rep_count, value, set_id, session, achieved_at FROM records "
                               + "WHERE exercise = ?", [exerciseId]).rows
    for (var i = 0; i < stored.length; i++) {
        var row = stored.item(i)
        var k = storedKey(row)
        var want = desired[k]
        if (!want) {
            Db.remove(tx, "records", row.id)
            continue
        }
        delete desired[k]
        if (Math.abs(want.value - row.value) > 1e-9 || want.set_id !== row.set_id || want.achieved_at !== row.achieved_at)
            putRecord(tx, row.id, exerciseId, want)
    }
    var added = []
    var id = Db.nextId(tx, "records") - 1
    for (var k2 in desired) {
        var r = desired[k2]
        id++
        putRecord(tx, id, exerciseId, r)
        added.push({ id: id, exercise: exerciseId, record_type: r.record_type, rep_count: r.rep_count,
                     value: r.value, weight: r.weight, reps: r.reps, achieved_at: r.achieved_at,
                     previous_value: r.previous_value })
    }
    return added
}

// check_and_record_prs: the records one newly logged set breaks, from
// SQL aggregates over the exercise's other eligible sets - the same
// comparisons as the replay, without walking the whole history.
function checkNewSet(tx, s, exerciseId, sessionId) {
    if (s.is_warmup || s.is_failure)
        return []
    var weight = Number(s.weight), reps = s.reps
    var base = " FROM sets WHERE exercise = ? AND is_warmup = 0 AND is_failure = 0 AND id != ?"
    var args = [exerciseId, s.id]
    function one(sql, extra) {
        var v = tx.executeSql("SELECT " + sql + " AS v" + base + (extra ? extra[0] : ""),
                              args.concat(extra ? extra[1] : [])).rows.item(0).v
        return v === null || v === undefined ? null : v
    }
    var found = []
    function add(type, value, previous, repCount) {
        found.push({ record_type: type, rep_count: repCount || null, value: value, previous_value: previous,
                     weight: weight, reps: reps, set_id: s.id, session: sessionId, achieved_at: s.performed_at })
    }
    var maxWeight = one("MAX(weight)")
    if (beats(weight, maxWeight))
        add("max_weight", weight, maxWeight)
    var repsAt = one("MAX(reps)", [" AND ABS(weight - ?) < 0.000001", [weight]])
    if (beats(reps, repsAt))
        add("rep_pr", reps, repsAt)
    REP_MILESTONES.forEach(function(milestone) {
        if (reps < milestone)
            return
        var previous = one("MAX(weight)", [" AND reps >= ?", [milestone]])
        if (beats(weight, previous))
            add("rep_specific_pr", weight, previous, milestone)
    })
    if (reps >= 1) {
        var e = estimate(weight, reps)
        var bestEstimate = one("MAX(ROUND(weight * (1 + reps / 30.0), 2))", [" AND reps >= 1", []])
        if (beats(e, bestEstimate))
            add("estimated_1rm", e, bestEstimate)
    }
    var volume = weight * reps
    var bestVolume = one("MAX(weight * reps)")
    if (beats(volume, bestVolume))
        add("set_volume", volume, bestVolume)

    var added = []
    var id = Db.nextId(tx, "records") - 1
    found.forEach(function(r) {
        id++
        putRecord(tx, id, exerciseId, r)
        added.push({ id: id, exercise: exerciseId, record_type: r.record_type, rep_count: r.rep_count,
                     value: r.value, weight: r.weight, reps: r.reps, achieved_at: r.achieved_at,
                     previous_value: r.previous_value })
    })

    // Session volume: one row per session, updated as it grows; only
    // its first appearance is news.
    var total = tx.executeSql("SELECT SUM(weight * reps) AS v FROM sets WHERE exercise = ? AND is_warmup = 0 "
                              + "AND is_failure = 0 AND session = ?", [exerciseId, sessionId]).rows.item(0).v || 0
    var bestOther = tx.executeSql("SELECT MAX(t) AS v FROM (SELECT SUM(weight * reps) AS t FROM sets WHERE exercise = ? "
                                  + "AND is_warmup = 0 AND is_failure = 0 AND session != ? GROUP BY session)",
                                  [exerciseId, sessionId]).rows.item(0).v
    if (bestOther === undefined)
        bestOther = null
    var existing = tx.executeSql("SELECT id FROM records WHERE exercise = ? AND record_type = 'session_volume' "
                                 + "AND session = ?", [exerciseId, sessionId]).rows
    var sessionRecord = { record_type: "session_volume", rep_count: null, value: total, weight: weight, reps: reps,
                          set_id: s.id, session: sessionId, achieved_at: s.performed_at }
    if (beats(total, bestOther)) {
        if (existing.length) {
            putRecord(tx, existing.item(0).id, exerciseId, sessionRecord)
        } else {
            id++
            putRecord(tx, id, exerciseId, sessionRecord)
            added.push({ id: id, exercise: exerciseId, record_type: "session_volume", rep_count: null, value: total,
                         weight: weight, reps: reps, achieved_at: s.performed_at, previous_value: bestOther })
        }
    }
    return added
}

// The records rebuild() added, as a set's `new_records` - read after
// the write's transaction.
function newRecords(added) {
    names = {}
    return added.sort(function(a, b) { return a.id - b.id })
                .map(function(r) { return toApi(r, r.previous_value) })
}

// Names looked up once per request (a page of records shares a few).
var names = {}

function exerciseName(id) {
    if (names[id] === undefined) {
        var row = Db.get("exercises", id)
        names[id] = row ? row.name : ""
    }
    return names[id]
}

function toApi(r, previous) {
    var out = {
        id: r.id, exercise: r.exercise, exercise_name: exerciseName(r.exercise), record_type: r.record_type,
        record_type_display: label(r.record_type), rep_count: r.rep_count, value: Http.dec(r.value),
        weight: Http.dec(r.weight), reps: r.reps, achieved_at: r.achieved_at
    }
    if (previous !== undefined)
        out.previous_value = Http.dec(previous)
    return out
}

function list(match, query) {
    names = {}
    var where = query.exercise ? " WHERE exercise = ?" : ""
    var args = query.exercise ? [Http.int(query.exercise)] : []
    return Http.paginateQuery(Db.scalar("SELECT COUNT(*) FROM records" + where, args) || 0, function(limit, offset) {
        return Db.read("SELECT data FROM records" + where + " ORDER BY achieved_at DESC, id DESC LIMIT ? OFFSET ?",
                       args.concat([limit, offset])).map(function(row) { return toApi(Db.parse(row)) })
    }, query, "records/")
}

function retrieve(match) {
    var row = Db.get("records", match[1])
    return row ? Http.ok(toApi(row)) : Http.notFound()
}

var routes = [
    ["GET", /^records\/$/, list],
    ["GET", /^records\/(\d+)\/$/, retrieve]
]
