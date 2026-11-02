.pragma library

// Shared, app-wide state and formatting helpers. A .pragma library script
// is one instance for every page that imports it, so the workout-name
// cache survives page pushes/pops.
.import "content.js" as Content

var LB_PER_KG = 2.20462262

// --- built-in content names ------------------------------------------------
// IronStack stores built-in exercises, programs and workouts in English and
// the web translates their names when showing them; the API returns them
// as stored. content.js carries the same translations (see
// tools/content-i18n/generate.py). A name with no translation - a user's
// own exercise, say - is shown as typed, the same as on the web.

function contentLanguage() {
    return Qt.locale().name.split("_")[0]
}

function contentName(name, language) {
    if (!name)
        return name
    var names = Content.catalog[language || contentLanguage()]
    return (names && names[name]) || name
}

var workoutNames = ({})

// Fetch the names of any ids not yet in `cache`, one GET per unknown id
// (a session carries only its workout's id), then call done(). A failed
// fetch leaves the id out, so the caller falls back to a placeholder.
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
// exercises/<id>/last-performance/ (the sets from the most recent completed
// session that included the exercise) as {sessionId, startedAt, sets} with
// the warm-ups left out, or null when there's nothing to show.
function lastTime(data) {
    if (!data || !data.session)
        return null
    var working = (data.sets || []).filter(function(s) { return !s.is_warmup })
    if (working.length === 0)
        return null
    return { sessionId: data.session, startedAt: data.started_at, sets: working }
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

// A shallow copy of an object, for assigning a changed map to a property.
function copy(object) {
    var result = {}
    for (var key in object)
        result[key] = object[key]
    return result
}

// True for an error that means "no connection" rather than a real refusal.
function isOffline(status) {
    return status === 0
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

// Default values for the next set of `pe`, in the same order as the
// IronStack web (apps.workouts.views._build_set_form): the last set logged
// for it in this session; otherwise the smart suggestion
// (performed-exercises/<id>/suggestion/) over the plan's target, reps from
// the bottom of the range. Last time's sets fill in only when that leaves
// no weight - the web leaves it empty then. Never more than a default -
// the user confirms every set.
// `before` is a lastTime() result or null, `suggestion` the API's
// suggestion (every field null without a prescription) or null.
function prefill(pe, before, suggestion) {
    var sets = pe.sets || []
    var last = sets.length > 0 ? sets[sets.length - 1] : null
    var first = firstSetDefault(pe, before, suggestion)
    if (!last)
        return first
    // After warm-ups only, the first working set's default is a better
    // guess than repeating the warm-up.
    if (workingSetCount(pe) === 0 && present(first.weightKg))
        return first
    return { weightKg: last.weight, reps: last.reps, rpe: last.rpe, rir: last.rir, source: "set" }
}

function present(value) {
    return value !== null && value !== undefined && value !== ""
}

function firstSetDefault(pe, before, suggestion) {
    var result = { weightKg: pe.target_weight, reps: pe.min_reps || pe.max_reps || null,
                   rpe: null, rir: null, source: present(pe.target_weight) ? "target" : "" }
    if (suggestion && present(suggestion.weight)) {
        result.weightKg = suggestion.weight
        result.source = "suggestion"
    }
    if (suggestion && present(suggestion.min_reps))
        result.reps = suggestion.min_reps
    if (!present(result.weightKg) && before && before.sets.length > 0) {
        result.weightKg = before.sets[0].weight
        result.reps = result.reps || before.sets[0].reps
        result.source = "previous"
        result.date = before.startedAt
    }
    return result
}

// "Suggested: 52.5 kg x 5-6", or "" when there's no suggested weight.
function suggestionText(suggestion, unitSystem, template) {
    if (!suggestion || !present(suggestion.weight))
        return ""
    var text = formatWeight(suggestion.weight, unitSystem)
    if (present(suggestion.min_reps)) {
        text += " x " + suggestion.min_reps
        if (present(suggestion.max_reps) && suggestion.max_reps !== suggestion.min_reps)
            text += "-" + suggestion.max_reps
    }
    return template.replace("%1", text)
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
