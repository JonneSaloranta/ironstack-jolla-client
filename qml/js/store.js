.pragma library

// Shared, app-wide state and formatting helpers. A .pragma library script
// is one instance for every page that imports it, so the exercise-name
// cache survives page pushes/pops.

var LB_PER_KG = 2.20462262

var exerciseNames = ({})

function exerciseName(id) {
    return exerciseNames[id] || ("#" + id)
}

function rememberExercises(list) {
    for (var i = 0; i < list.length; i++)
        exerciseNames[list[i].id] = list[i].name
}

var workoutNames = ({})

// Fetch the names of any ids not yet in `cache`, one GET per unknown id
// (the API returns only ids on prescriptions/records/sessions - see
// IronStack issue #19), then call done(). A failed fetch leaves the id
// out, so the caller falls back to a placeholder.
function ensureNames(api, cache, endpoint, ids, done) {
    var missing = []
    for (var i = 0; i < ids.length; i++) {
        if (ids[i] && cache[ids[i]] === undefined && missing.indexOf(ids[i]) < 0)
            missing.push(ids[i])
    }
    if (missing.length === 0) {
        done()
        return
    }
    var remaining = missing.length
    missing.forEach(function(id) {
        api.request("GET", endpoint + id + "/", null, function(ok, status, data) {
            if (ok)
                cache[data.id] = data.name
            remaining--
            if (remaining === 0)
                done()
        })
    })
}

function ensureExercises(api, ids, done) {
    ensureNames(api, exerciseNames, "exercises/", ids, done)
}

function ensureWorkouts(api, ids, done) {
    ensureNames(api, workoutNames, "workouts/", ids, done)
}

// Follow a paginated list endpoint to the end. onPage(results) is called
// per page; done(ok, error) once at the end.
function fetchAll(api, path, onPage, done) {
    api.request("GET", path, null, function(ok, status, data, error) {
        if (!ok) {
            done(false, error)
            return
        }
        onPage(data.results || [])
        if (data.next)
            fetchAll(api, data.next, onPage, done)
        else
            done(true, "")
    })
}

// --- units --------------------------------------------------------------
// The API is always kilograms (docs/API.md "Canonical units, always");
// conversion is purely a display concern.

function isImperial(unitSystem) {
    return unitSystem === "imperial"
}

function weightUnit(unitSystem) {
    return isImperial(unitSystem) ? "lb" : "kg"
}

function kgToDisplay(kg, unitSystem) {
    var value = parseFloat(kg)
    if (isNaN(value))
        return NaN
    return isImperial(unitSystem) ? value * LB_PER_KG : value
}

function displayToKg(value, unitSystem) {
    var number = parseFloat(String(value).replace(",", "."))
    if (isNaN(number))
        return NaN
    var kg = isImperial(unitSystem) ? number / LB_PER_KG : number
    return Math.round(kg * 100) / 100
}

function formatNumber(value) {
    if (isNaN(value))
        return "-"
    var rounded = Math.round(value * 100) / 100
    return String(rounded)
}

function formatWeight(kg, unitSystem) {
    if (kg === null || kg === undefined || kg === "")
        return "-"
    return formatNumber(kgToDisplay(kg, unitSystem)) + " " + weightUnit(unitSystem)
}

// --- time -----------------------------------------------------------------
// Dates and times are formatted in the pages with Silica's Format.formatDate,
// which follows the device's locale and 12/24-hour setting.

function formatDuration(seconds) {
    seconds = Math.max(0, Math.floor(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    var s = seconds % 60
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

function elapsedSince(iso) {
    if (!iso)
        return 0
    return (Date.now() - new Date(iso).getTime()) / 1000
}

function formatHoursMinutes(seconds) {
    seconds = Math.max(0, Math.floor(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    return h + ":" + (m < 10 ? "0" + m : m)
}

// --- previous performance -------------------------------------------------
// The working sets from the most recent completed session (other than
// currentSessionId) that included exerciseId, or null. `sessions` is a
// newest-first list as returned by sessions/. Only what's in that list is
// searched - a dedicated endpoint is IronStack issue #20.
function previousPerformance(sessions, exerciseId, currentSessionId) {
    for (var i = 0; i < sessions.length; i++) {
        var session = sessions[i]
        if (session.id === currentSessionId || session.status !== "completed")
            continue
        var performed = session.performed_exercises || []
        for (var j = 0; j < performed.length; j++) {
            if (performed[j].exercise !== exerciseId)
                continue
            var working = (performed[j].sets || []).filter(function(s) { return !s.is_warmup })
            if (working.length > 0)
                return { sessionId: session.id, startedAt: session.started_at, sets: working }
        }
    }
    return null
}

// "3 x 5 @ 80 kg" when every set matches, otherwise each set listed:
// "80 kg x 5, 80 kg x 5, 75 kg x 6".
function summarizeSets(sets, unitSystem) {
    if (!sets || sets.length === 0)
        return ""
    var same = sets.every(function(s) {
        return parseFloat(s.weight) === parseFloat(sets[0].weight) && s.reps === sets[0].reps
    })
    if (same)
        return sets.length + " x " + sets[0].reps + " @ " + formatWeight(sets[0].weight, unitSystem)
    return sets.map(function(s) { return formatWeight(s.weight, unitSystem) + " x " + s.reps }).join(", ")
}

var recentSessions = null
var recentSessionsLoadedAt = 0
var RECENT_SESSIONS_MAX_AGE_MS = 5 * 60 * 1000

// Newest page of sessions, cached for a few minutes; finishing a session
// calls invalidateRecentSessions() so the next one sees it.
function loadRecentSessions(api, done) {
    if (recentSessions !== null && Date.now() - recentSessionsLoadedAt < RECENT_SESSIONS_MAX_AGE_MS) {
        done(recentSessions)
        return
    }
    api.request("GET", "sessions/", null, function(ok, status, data) {
        if (ok) {
            recentSessions = data.results || []
            recentSessionsLoadedAt = Date.now()
        }
        done(recentSessions || [])
    })
}

// True for an error that means "no connection" rather than a real refusal.
function isOffline(status) {
    return status === 0
}

function invalidateRecentSessions() {
    recentSessions = null
}

// "Rep-specific PR (5RM)" - without the rep count a lifter's 1RM, 3RM and
// 5RM records would look identical.
function recordLabel(record, repMaxText) {
    if (record.rep_count)
        return record.record_type_display + " (" + repMaxText.replace("%1", record.rep_count) + ")"
    return record.record_type_display
}

// --- session logic shared by the training page and the full view -------

// Same rule as IronStack's apps.workouts.services.is_performed_exercise_complete:
// a prescribed exercise is done once it has its set_count of sets (warm-ups
// don't count here), a freeform addition once it has any set at all.
function isExerciseComplete(pe) {
    var sets = pe.sets || []
    if (pe.set_count)
        return sets.filter(function(s) { return !s.is_warmup }).length >= pe.set_count
    return sets.length > 0
}

// Index of the first exercise with sets left to log, or -1 when all are done.
function firstIncompleteIndex(exercises) {
    for (var i = 0; i < exercises.length; i++) {
        if (!isExerciseComplete(exercises[i]))
            return i
    }
    return -1
}

// The session's exercises with sets still waiting in the sync queue
// appended, marked `pending: true`, so a set logged offline shows up right
// away. `queueItems` is syncQueue.items.
function mergePendingSets(session, queueItems) {
    if (!session)
        return []
    return session.performed_exercises.map(function(pe) {
        var sets = (pe.sets || []).slice()
        var highest = sets.reduce(function(max, s) { return Math.max(max, s.set_number) }, 0)
        queueItems.forEach(function(item) {
            if (item.method !== "POST" || item.path !== "sets/" || !item.body
                    || item.body.performed_exercise !== pe.id)
                return
            highest++
            sets.push({
                id: "pending-" + item.id,
                pending: true,
                set_number: highest,
                weight: item.body.weight,
                reps: item.body.reps,
                rpe: item.body.rpe,
                rir: item.body.rir,
                is_warmup: !!item.body.is_warmup,
                is_failure: !!item.body.is_failure,
                notes: item.body.notes || ""
            })
        })
        var copy = {}
        for (var key in pe)
            copy[key] = pe[key]
        copy.sets = sets
        return copy
    })
}

// "completed"/"abandoned" when ending this session is waiting in the queue,
// otherwise "".
function pendingSessionEnd(queueItems, sessionId) {
    for (var i = queueItems.length - 1; i >= 0; i--) {
        var item = queueItems[i]
        if (item.method === "PATCH" && item.path === "sessions/" + sessionId + "/" && item.body)
            return item.body.status || ""
    }
    return ""
}

// Default values for the next set of `pe`, in order of preference: the last
// set logged for it in this session, the same set from last time, the
// plan's target. Never more than a default - the user confirms every set.
// `before` is a previousPerformance() result or null.
function prefill(pe, before) {
    var sets = pe.sets || []
    var last = sets.length > 0 ? sets[sets.length - 1] : null
    var working = sets.filter(function(s) { return !s.is_warmup }).length
    var beforeSet = before && before.sets.length > 0
            ? before.sets[Math.min(working, before.sets.length - 1)] : null
    // After warm-ups only, last time's working set is the better guess.
    if (last && !(last.is_warmup && beforeSet))
        return { weightKg: last.weight, reps: last.reps, rpe: last.rpe, rir: last.rir, source: "set" }
    if (beforeSet)
        return { weightKg: beforeSet.weight, reps: beforeSet.reps, rpe: null, rir: null,
                 source: "previous", date: before.startedAt }
    return { weightKg: pe.target_weight, reps: pe.max_reps || pe.min_reps || null, rpe: null, rir: null,
             source: pe.target_weight ? "target" : "" }
}

function targetText(pe, unitSystem) {
    if (!pe.set_count)
        return ""
    var reps = pe.min_reps && pe.max_reps && pe.min_reps !== pe.max_reps
            ? pe.min_reps + "-" + pe.max_reps : (pe.max_reps || pe.min_reps || "?")
    var text = pe.set_count + " x " + reps
    if (pe.target_weight)
        text += " @ " + formatWeight(pe.target_weight, unitSystem)
    return text
}

function workingSetCount(pe) {
    return (pe.sets || []).filter(function(s) { return !s.is_warmup }).length
}

// Which list a program from programs/ belongs in, matching IronStack's own
// program page: "own" (the user's, or shared by their coach), "template"
// (a built-in template), or "" - an ownerless program that isn't a
// template, which the web page doesn't list either.
function programGroup(program) {
    if (program.owner !== null && program.owner !== undefined)
        return "own"
    return program.is_template ? "template" : ""
}
