.pragma library

// Shared, app-wide state and formatting helpers. A .pragma library script
// is one instance for every page that imports it, so the workout-name
// cache survives page pushes/pops.
.import "content.js" as Content

var LB_PER_KG = 2.20462262

// --- navigation --------------------------------------------------------------

// Runs action() once the page stack is idle. A page pushed from a reply
// can come while a dialog is still closing, and Silica drops a push made
// during a transition ("cannot push while transition is in progress"):
// the page a new recipe, program or routine should open to never came.
function whenIdle(pageStack, action) {
    if (!pageStack.busy)
        return action()
    function idle() {
        if (pageStack.busy)
            return
        pageStack.busyChanged.disconnect(idle)
        action()
    }
    pageStack.busyChanged.connect(idle)
}

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

// An exercise's strength trend from analytics/exercises/<id>/: one point
// per training day (its best set's estimated 1RM), sessions and volume.
// { points: [{x, y}], sessionCount, volume } - kg.
function exerciseTrend(analytics) {
    return {
        points: (analytics.sessions || []).map(function(s) {
            return { x: parseDate(s.date).getTime(), y: parseNumber(s.estimated_one_rep_max) }
        }).filter(function(p) { return !isNaN(p.y) }).sort(function(a, b) { return a.x - b.x }),
        sessionCount: analytics.session_count || 0,
        volume: parseNumber(analytics.total_volume) || 0
    }
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
var dietPlansChanged = false

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
                    return { id: item.id, name: contentName(item.name), storedName: item.name }
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

// --- stretching --------------------------------------------------------------

var STRETCH_PREPARE_SECONDS = 5

// The guided timer's steps for a routine, like the web's
// apps.stretching.services.timer_steps: per stretch a 5 s "prepare", then a
// "hold" per set and side, with a "rest" between holds when the item has
// one. An item's hold falls back to the stretch's default.
// `stretches` maps stretch id -> stretch.
function stretchSteps(items, stretches) {
    var steps = []
    ;(items || []).slice().sort(function(a, b) { return a.order - b.order || a.id - b.id }).forEach(function(item) {
        var stretch = stretches[item.stretch] || {}
        var perSide = item.per_side !== undefined ? item.per_side : stretch.per_side
        var sides = perSide ? ["left", "right"] : [""]
        var hold = present(item.hold_seconds) ? item.hold_seconds : (stretch.default_hold_seconds || 30)
        var sets = item.sets || 1
        var holds = []
        for (var set = 1; set <= sets; set++)
            sides.forEach(function(side) { holds.push({ set: set, side: side }) })
        var performed = item.performed || null
        steps.push({ kind: "prepare", stretch: item.stretch, seconds: STRETCH_PREPARE_SECONDS,
                     set: 1, sets: sets, side: sides[0], lastOfStretch: false, performed: performed })
        holds.forEach(function(h, index) {
            var last = index === holds.length - 1
            steps.push({ kind: "hold", stretch: item.stretch, seconds: hold, set: h.set, sets: sets,
                         side: h.side, lastOfStretch: last, performed: performed })
            if (!last && item.rest_seconds)
                steps.push({ kind: "rest", stretch: item.stretch, seconds: item.rest_seconds, set: h.set,
                             sets: sets, side: h.side, lastOfStretch: false, performed: performed })
        })
    })
    return steps
}

// --- cool-down suggestion (apps.stretching.services.suggest_cooldown) --------

var MAX_SUGGESTED_STRETCHES = 6
var MIN_ROUTINE_COVERAGE = 0.5
// Rest between holds of a stretch picked outside a routine.
var AD_HOC_REST_SECONDS = 10

// Planned time for one stretch: every hold, plus rest between them.
function itemSeconds(holdSeconds, sets, perSide, restSeconds) {
    var holds = (sets || 1) * (perSide ? 2 : 1)
    return holds * holdSeconds + (holds - 1) * (restSeconds || 0)
}

function routineSeconds(routine, stretches) {
    return (routine.items || []).reduce(function(total, item) {
        var stretch = stretches[item.stretch] || {}
        var hold = present(item.hold_seconds) ? item.hold_seconds : (stretch.default_hold_seconds || 30)
        return total + itemSeconds(hold, item.sets, stretch.per_side, item.rest_seconds)
    }, 0)
}

// What to stretch after a workout that trained `muscleIds` (primary muscle
// groups, in name order): the routine whose static stretches cover most of
// them - ties to the shorter - if it covers at least half, else one static
// stretch per muscle from the library, built-in ones first, at most six.
// `routines` with their items, `stretches` id -> stretch. Returns
// { routine, seconds } or { stretches: [ids], seconds }, or null.
function suggestCooldown(muscleIds, routines, stretches) {
    if (!muscleIds || muscleIds.length === 0)
        return null
    var best = null
    var bestCoverage = 0
    var bestSeconds = 0
    ;(routines || []).slice().sort(function(a, b) { return a.name.localeCompare(b.name) }).forEach(function(routine) {
        var covered = {}
        ;(routine.items || []).forEach(function(item) {
            var stretch = stretches[item.stretch]
            if (!stretch || stretch.kind !== "static")
                return
            ;(stretch.muscle_groups || []).forEach(function(group) {
                if (muscleIds.indexOf(group) >= 0)
                    covered[group] = true
            })
        })
        var coverage = Object.keys(covered).length / muscleIds.length
        var seconds = routineSeconds(routine, stretches)
        if (coverage > bestCoverage || (coverage === bestCoverage && best !== null && seconds < bestSeconds)) {
            best = routine
            bestCoverage = coverage
            bestSeconds = seconds
        }
    })
    if (best !== null && bestCoverage >= MIN_ROUTINE_COVERAGE)
        return { routine: best, seconds: bestSeconds }

    var candidates = []
    for (var id in stretches) {
        if (stretches[id].kind === "static" && stretches[id].active !== false)
            candidates.push(stretches[id])
    }
    candidates.sort(function(a, b) {
        return present(a.owner) - present(b.owner) || a.name.localeCompare(b.name)
    })
    var chosen = []
    for (var m = 0; m < muscleIds.length && chosen.length < MAX_SUGGESTED_STRETCHES; m++) {
        for (var c = 0; c < candidates.length; c++) {
            if (chosen.indexOf(candidates[c]) < 0 && (candidates[c].muscle_groups || []).indexOf(muscleIds[m]) >= 0) {
                chosen.push(candidates[c])
                break
            }
        }
    }
    if (chosen.length === 0)
        return null
    return {
        stretches: chosen.map(function(s) { return s.id }),
        seconds: chosen.reduce(function(total, s) {
            return total + itemSeconds(s.default_hold_seconds || 30, 1, s.per_side, AD_HOC_REST_SECONDS)
        }, 0)
    }
}

// A guided session's stretches still to do (stretch-sessions/start/), as
// items for stretchSteps(): its snapshot of hold, sets, rest and per side,
// each step carrying the performed stretch's id to mark.
function sessionItems(session) {
    return ((session && session.performed_stretches) || []).filter(function(ps) {
        return ps.status === "pending"
    }).map(function(ps) {
        return { id: ps.id, order: ps.order, stretch: ps.stretch, hold_seconds: ps.target_hold_seconds,
                 sets: ps.sets, rest_seconds: ps.rest_seconds, per_side: ps.per_side, performed: ps.id }
    })
}

// The stretch library (id -> stretch), fetched once; set
// `stretchesChanged` after a stretch is created, edited or deactivated.
var stretches = null
var stretchesChanged = false
// Routines and sessions changed somewhere; the stretching pages reload.
var stretchingChanged = false

function ensureStretches(api, done) {
    if (stretches !== null && !stretchesChanged)
        return done(true, "")
    var found = {}
    fetchAll(api, "stretches/?page_size=100", function(results) {
        results.forEach(function(stretch) { found[stretch.id] = stretch })
    }, function(ok, error) {
        if (ok) {
            stretches = found
            stretchesChanged = false
        }
        done(ok, error)
    })
}

function stretchName(id) {
    return stretches && stretches[id] ? contentName(stretches[id].name) : "#" + id
}

// The index of the first step of the next stretch after `index`, or
// steps.length - for "Skip stretch".
function nextStretchStep(steps, index) {
    var current = steps[index] ? steps[index].stretch : null
    var at = index + 1
    while (at < steps.length && !(steps[at].kind === "prepare" && (steps[at].stretch !== current
                                                                  || steps[at - 1].lastOfStretch)))
        at++
    return at
}

// The web's stretching summary (apps.stretching.services.summarize) of
// completed sessions: { count, seconds, weekCount, weekSeconds, streak }.
// The streak counts days in a row ending today, or yesterday so it isn't
// broken before today's stretch.
function stretchSummary(sessions, today) {
    var completed = (sessions || []).filter(function(s) { return s.status === "completed" })
    var weekStart = isoDate(addDays(today, -6))
    var todayIso = isoDate(today)
    var result = { count: completed.length, seconds: 0, weekCount: 0, weekSeconds: 0, streak: 0 }
    var days = {}
    completed.forEach(function(s) {
        var seconds = parseDuration(s.duration) || 0
        result.seconds += seconds
        if (s.date >= weekStart && s.date <= todayIso) {
            result.weekCount++
            result.weekSeconds += seconds
        }
        days[s.date] = true
    })
    var day = days[todayIso] ? today : addDays(today, -1)
    while (days[isoDate(day)]) {
        result.streak++
        day = addDays(day, -1)
    }
    return result
}

// Minutes of completed stretching per week for the last `weeks` weeks
// (Monday first), oldest first - the web's weekly_minutes:
// [{ monday: Date, minutes }].
function weeklyStretchMinutes(sessions, today, weeks) {
    var thisMonday = addDays(today, -((today.getDay() + 6) % 7))
    var rows = []
    for (var i = weeks - 1; i >= 0; i--)
        rows.push({ monday: addDays(thisMonday, -7 * i), seconds: 0 })
    ;(sessions || []).forEach(function(session) {
        if (session.status !== "completed")
            return
        var day = parseDate(session.date)
        var monday = addDays(day, -((day.getDay() + 6) % 7))
        for (var j = 0; j < rows.length; j++) {
            if (rows[j].monday.getTime() === monday.getTime())
                rows[j].seconds += parseDuration(session.duration) || 0
        }
    })
    return rows.map(function(row) { return { monday: row.monday, minutes: Math.round(row.seconds / 60) } })
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

// A record's value with its unit: kg (or lb) for every type except
// rep_pr, a plain rep count - apps.records.services.display_value.
function recordValueText(record, unitSystem, repsTemplate) {
    if (record.record_type === "rep_pr")
        return repsTemplate.replace("%1", parseInt(record.value, 10))
    return formatWeight(record.value, unitSystem)
}

// --- programs ----------------------------------------------------------------

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

// Bodies of the writes to `path` still waiting in the sync queue, oldest
// first, each with `pendingId` (the queue item's id). `queueItems` is
// syncQueue.items.
function pendingPosts(queueItems, path) {
    return (queueItems || []).filter(function(item) {
        return item.method === "POST" && item.path === path && item.body
    }).map(function(item) {
        var body = JSON.parse(JSON.stringify(item.body))
        body.pendingId = item.id
        return body
    })
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

// The user ids of the user's coaches (coaching/coaches/), as last read:
// programs/ also lists the programs a coach shares, owned by the coach.
var coachIds = []

// Which list a program from programs/ belongs in, matching IronStack's own
// program page: "own", "template" (a built-in template), or "" - a
// program a coach shares (it's under Coaching, imported from there as an
// own copy; the web's list leaves it out too) or an ownerless one that
// isn't a template.
function programGroup(program, coaches) {
    if (program.owner !== null && program.owner !== undefined)
        return (coaches || coachIds).indexOf(program.owner) >= 0 ? "" : "own"
    return program.is_template ? "template" : ""
}
