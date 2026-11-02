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

// --- analytics -------------------------------------------------------------
// The web's analytics date ranges (apps/analytics/dateranges.py).
var RANGE_DAYS = { "7d": 7, "30d": 30, "3m": 90, "6m": 182, "1y": 365, "all": 0 }

// The first day of `range` ending today, or null for all time.
function rangeStart(range, today) {
    var days = RANGE_DAYS[range]
    return days ? addDays(today, -(days - 1)) : null
}

// Estimated one-rep max, Epley like the web (apps/records/one_rep_max.py).
function estimateOneRepMax(weight, reps) {
    var w = parseNumber(weight)
    if (isNaN(w) || !(reps >= 1))
        return NaN
    return round(w * (1 + reps / 30), 2)
}

// An exercise's strength trend from completed sessions, like the web's
// exercise_one_rm_trend: one point per day (that day's best estimate of a
// working set that wasn't a failure), and the summary of
// exercise_summary: sessions and volume (failed sets count there).
// Returns { points: [{x, y}], sessionCount, volume } - kg.
function exerciseTrend(sessions, exerciseId) {
    var best = {}
    var sessionIds = {}
    var volume = 0
    sessions.forEach(function(session) {
        if (session.status !== "completed")
            return
        var started = new Date(session.started_at)
        var day = isoDate(started)
        ;(session.performed_exercises || []).forEach(function(pe) {
            if (pe.exercise !== exerciseId)
                return
            ;(pe.sets || []).forEach(function(set) {
                if (set.is_warmup)
                    return
                sessionIds[session.id] = true
                volume += parseNumber(set.weight) * set.reps
                if (set.is_failure)
                    return
                var estimate = estimateOneRepMax(set.weight, set.reps)
                if (!isNaN(estimate) && (best[day] === undefined || estimate > best[day].y))
                    best[day] = { x: parseDate(day).getTime(), y: estimate }
            })
        })
    })
    var points = []
    for (var day in best)
        points.push(best[day])
    points.sort(function(a, b) { return a.x - b.x })
    return { points: points, sessionCount: Object.keys(sessionIds).length, volume: round(volume, 2) }
}

// --- small lookup lists ----------------------------------------------------
// Muscle groups and equipment (exercises context): fetched once, names
// translated like the web's.

var lookups = { muscleGroups: null, equipment: null }
// Set after an exercise is created, edited or removed, so lists reload.
var exercisesChanged = false
// Same for body measurements and their types.
var measurementsChanged = false
var activitiesChanged = false

function ensureLookups(api, done) {
    var kinds = [["muscleGroups", "muscle-groups/"], ["equipment", "equipment/"]]
    var remaining = 0
    kinds.forEach(function(kind) {
        if (lookups[kind[0]] !== null)
            return
        remaining++
        var items = []
        fetchAll(api, kind[1] + "?page_size=100", function(results) {
            items = items.concat(results)
        }, function(ok) {
            if (ok) {
                lookups[kind[0]] = items.map(function(item) {
                    return { id: item.id, name: contentName(item.name) }
                }).sort(function(a, b) { return a.name.localeCompare(b.name) })
            }
            remaining--
            if (remaining === 0)
                done()
        })
    })
    if (remaining === 0)
        done()
}

// `kind`'s list or []. `dependency` is only there so a binding re-reads it
// once the list has been loaded.
function lookupList(kind, dependency) {
    return lookups[kind] || []
}

function lookupName(kind, id) {
    var list = lookups[kind] || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return list[i].name
    }
    return ""
}

function muscleGroupName(id) {
    return lookupName("muscleGroups", id)
}

function equipmentName(id) {
    return lookupName("equipment", id)
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

// Lengths are canonical meters, shown as cm or inches; distances meters,
// shown as km or miles - the same factors and rounding as IronStack's
// apps/core/units.py and apps/measurements/units.py.
var M_PER_INCH = 0.0254
var M_PER_MILE = 1609.344

function parseNumber(value) {
    return parseFloat(String(value).replace(",", "."))
}

function round(value, places) {
    var factor = Math.pow(10, places)
    return Math.round(value * factor) / factor
}

function lengthUnit(unitSystem) {
    return isImperial(unitSystem) ? "in" : "cm"
}

function distanceUnit(unitSystem) {
    return isImperial(unitSystem) ? "mi" : "km"
}

// A body measurement's unit label by its type's unit_kind.
function measurementUnit(unitKind, unitSystem) {
    if (unitKind === "weight")
        return weightUnit(unitSystem)
    if (unitKind === "length")
        return lengthUnit(unitSystem)
    if (unitKind === "percentage")
        return "%"
    return ""
}

// Canonical value -> display number (weights 2 decimals, lengths 1).
function measurementToDisplay(value, unitKind, unitSystem) {
    var number = parseNumber(value)
    if (isNaN(number))
        return NaN
    if (unitKind === "weight")
        return round(kgToDisplay(number, unitSystem), 2)
    if (unitKind === "length")
        return round(isImperial(unitSystem) ? number / M_PER_INCH : number * 100, 1)
    return round(number, 2)
}

// Typed display value -> canonical value for the API (lengths 4 decimals).
function displayToMeasurement(value, unitKind, unitSystem) {
    var number = parseNumber(value)
    if (isNaN(number))
        return NaN
    if (unitKind === "weight")
        return displayToKg(number, unitSystem)
    if (unitKind === "length")
        return round(isImperial(unitSystem) ? number * M_PER_INCH : number / 100, 4)
    return round(number, 2)
}

function formatMeasurement(value, unitKind, unitSystem) {
    var number = measurementToDisplay(value, unitKind, unitSystem)
    if (isNaN(number))
        return "-"
    var unit = measurementUnit(unitKind, unitSystem)
    return formatNumber(number) + (unit === "%" ? " %" : unit ? " " + unit : "")
}

function metersToDistance(meters, unitSystem) {
    var number = parseNumber(meters)
    if (isNaN(number))
        return NaN
    return round(number / (isImperial(unitSystem) ? M_PER_MILE : 1000), 2)
}

function distanceToMeters(value, unitSystem) {
    var number = parseNumber(value)
    if (isNaN(number))
        return NaN
    return round(number * (isImperial(unitSystem) ? M_PER_MILE : 1000), 2)
}

function formatDistance(meters, unitSystem) {
    if (meters === null || meters === undefined || meters === "")
        return ""
    return formatNumber(metersToDistance(meters, unitSystem)) + " " + distanceUnit(unitSystem)
}

// --- body measurements -----------------------------------------------------

var BODY_WEIGHT_TYPE_NAME = "Body weight"

// The built-in body weight type (the web's dashboard and BMI use it).
function isBodyWeightType(type) {
    return !!type && type.name === BODY_WEIGHT_TYPE_NAME && !present(type.owner)
}

// The web's statistics for one type's readings (any order), canonical:
// { count, latest, latestAt, first, change, min, max, average } or null.
function measurementStats(readings) {
    if (!readings || readings.length === 0)
        return null
    var sorted = readings.slice().sort(function(a, b) {
        return new Date(a.recorded_at) - new Date(b.recorded_at)
    })
    var values = sorted.map(function(r) { return parseNumber(r.value) })
    var sum = values.reduce(function(total, v) { return total + v }, 0)
    var first = values[0]
    var latest = values[values.length - 1]
    return {
        count: values.length,
        latest: latest,
        latestAt: sorted[sorted.length - 1].recorded_at,
        first: first,
        change: round(latest - first, 4),
        min: Math.min.apply(null, values),
        max: Math.max.apply(null, values),
        average: round(sum / values.length, 4)
    }
}

// BMI from kg and meters, one decimal (apps/core/bmi.py), or NaN.
function bmi(weightKg, heightM) {
    var w = parseNumber(weightKg)
    var h = parseNumber(heightM)
    if (isNaN(w) || isNaN(h) || h <= 0)
        return NaN
    return round(w / (h * h), 1)
}

// "underweight", "normal", "overweight" or "obese" - the web's ranges.
function bmiCategory(value) {
    if (isNaN(value))
        return ""
    if (value < 18.5)
        return "underweight"
    if (value < 25)
        return "normal"
    if (value < 30)
        return "overweight"
    return "obese"
}

// --- activities --------------------------------------------------------------

// "1h 15min", "45min" or "<1min", rounded to the minute - the web's
// `duration` filter (apps/core/templatetags/core_extras.py).
function formatMinutes(seconds) {
    if (isNaN(seconds) || seconds === null)
        return ""
    var total = Math.round(seconds / 60)
    var hours = Math.floor(total / 60)
    var minutes = total % 60
    if (hours && minutes)
        return hours + "h " + minutes + "min"
    if (hours)
        return hours + "h"
    if (minutes)
        return minutes + "min"
    return "<1min"
}

// The web's summary of one type's activities: count, total seconds, and
// total meters and calories - null when none of them has one.
function activitySummary(activities) {
    var summary = { count: 0, duration: 0, distance: null, calories: null }
    ;(activities || []).forEach(function(a) {
        summary.count++
        summary.duration += parseDuration(a.duration) || 0
        if (present(a.distance))
            summary.distance = round((summary.distance || 0) + parseNumber(a.distance), 2)
        if (present(a.calories))
            summary.calories = (summary.calories || 0) + a.calories
    })
    return summary
}

// --- durations as DRF sends them: "[DD ]HH:MM:SS[.uuuuuu]" ----------------

function parseDuration(text) {
    if (text === null || text === undefined || text === "")
        return NaN
    var days = 0
    var rest = String(text).trim()
    var space = rest.indexOf(" ")
    if (space > 0) {
        days = parseInt(rest.substring(0, space), 10)
        rest = rest.substring(space + 1)
    }
    var parts = rest.split(":")
    if (parts.length !== 3)
        return NaN
    return days * 86400 + parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60
            + Math.floor(parseFloat(parts[2]))
}

function toDuration(seconds) {
    seconds = Math.max(0, Math.round(seconds))
    var h = Math.floor(seconds / 3600)
    var m = Math.floor((seconds % 3600) / 60)
    var s = seconds % 60
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return pad(h) + ":" + pad(m) + ":" + pad(s)
}

// "2026-11-02" for a Date, in local time (the API's DateField).
function isoDate(date) {
    function pad(n) { return n < 10 ? "0" + n : String(n) }
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function addDays(date, days) {
    var result = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    result.setDate(result.getDate() + days)
    return result
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

// "2026-11-02" (a date without a time, as up-next/ gives it) as local
// midnight - new Date("2026-11-02") would be UTC midnight, the day before
// west of Greenwich.
function parseDate(iso) {
    var parts = String(iso).split("-")
    return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10))
}

function isToday(iso, now) {
    var day = parseDate(iso)
    return day.getFullYear() === now.getFullYear() && day.getMonth() === now.getMonth()
            && day.getDate() === now.getDate()
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

// The records a just-logged set made: PR detection gives them the set's
// performed_at as achieved_at (apps.records.services), so they're the
// ones from records/ (newest first) with exactly that time.
function recordsForSet(records, performedAt) {
    return (records || []).filter(function(r) { return r.achieved_at === performedAt })
}

// A record's value with its unit: kg (or lb) for every type except
// rep_pr, a plain rep count - apps.records.services.display_value.
function recordValueText(record, unitSystem, repsTemplate) {
    if (record.record_type === "rep_pr")
        return repsTemplate.replace("%1", parseInt(record.value, 10))
    return formatWeight(record.value, unitSystem)
}

// --- programs ----------------------------------------------------------------

var PRESCRIPTION_FIELDS = ["exercise", "order", "set_count", "min_reps", "max_reps", "target_weight",
                           "target_rpe", "target_rir", "progression_method", "weight_increment",
                           "percentage_target", "notes"]

// Copy a program (a template, say) into a new program of your own, like
// the web's Copy (apps.programs.services.copy_program: same name,
// description and kind, not a template, every workout and prescription).
// The API has no copy endpoint (IronStack #32), so it's one request per
// row; if one fails the half-made copy is deleted again.
// done(ok, newProgramId, error)
function copyProgram(api, program, done) {
    var steps = []
    var newProgramId = null
    var workoutIds = {}

    steps.push(function(next) {
        api.request("POST", "programs/", {
            name: program.name, description: program.description || "",
            is_continuous: !!program.is_continuous, is_template: false
        }, function(ok, status, data, error) {
            if (!ok)
                return next(error)
            newProgramId = data.id
            next()
        })
    })
    ;(program.workouts || []).forEach(function(workout) {
        steps.push(function(next) {
            api.request("POST", "workouts/", {
                program: newProgramId, name: workout.name, order: workout.order,
                scheduled_weekday: present(workout.scheduled_weekday) ? workout.scheduled_weekday : null,
                notes: workout.notes || ""
            }, function(ok, status, data, error) {
                if (!ok)
                    return next(error)
                workoutIds[workout.id] = data.id
                next()
            })
        })
        ;(workout.prescriptions || []).forEach(function(prescription) {
            steps.push(function(next) {
                var body = { workout: workoutIds[workout.id] }
                PRESCRIPTION_FIELDS.forEach(function(field) {
                    body[field] = present(prescription[field]) ? prescription[field] : (field === "notes" ? "" : null)
                })
                api.request("POST", "prescriptions/", body, function(ok, status, data, error) {
                    next(ok ? undefined : error)
                })
            })
        })
    })

    var at = 0
    function next(error) {
        if (error !== undefined) {
            if (newProgramId === null)
                return done(false, null, error)
            api.request("DELETE", "programs/" + newProgramId + "/", null, function() {
                done(false, null, error)
            })
            return
        }
        if (at === steps.length)
            return done(true, newProgramId, "")
        steps[at++](next)
    }
    next()
}

// The other row to swap `index` with when moving it up (-1) or down (+1)
// in an `order`-sorted list, or -1 at the end of the list.
function swapTarget(count, index, direction) {
    var other = index + direction
    return other >= 0 && other < count ? other : -1
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
