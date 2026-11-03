.pragma library
// The web's Progress page (apps/analytics/services.py), worked out from
// completed sessions, records and body measurements - the API has no
// analytics over time (IronStack #35). Pure functions; the page fetches.
// Weights and volumes stay canonical kg here, the page converts.
.import "store.js" as Store

// Sets that count toward training load: working sets of completed
// sessions started in [start, end] (Dates, start null = no lower bound).
// A failed set still counts - the work happened (_training_sets).
// Calls fn(set, performedExercise, session) for each.
function eachTrainingSet(sessions, start, end, fn) {
    ;(sessions || []).forEach(function(session) {
        if (!inRange(session, start, end))
            return
        ;(session.performed_exercises || []).forEach(function(pe) {
            ;(pe.sets || []).forEach(function(set) {
                if (!set.is_warmup)
                    fn(set, pe, session)
            })
        })
    })
}

function inRange(session, start, end) {
    if (session.status !== "completed")
        return false
    var day = Store.isoDate(new Date(session.started_at))
    return (!start || day >= Store.isoDate(start)) && (!end || day <= Store.isoDate(end))
}

function setVolume(set) {
    var weight = Store.parseNumber(set.weight)
    return (isNaN(weight) ? 0 : weight) * (set.reps || 0)
}

// Workouts, training time (seconds, sessions with an end) and volume.
function trainingSummary(sessions, start, end) {
    var summary = { sessionCount: 0, duration: 0, volume: 0 }
    ;(sessions || []).forEach(function(session) {
        if (!inRange(session, start, end))
            return
        summary.sessionCount++
        if (session.ended_at)
            summary.duration += Math.max(0, (new Date(session.ended_at) - new Date(session.started_at)) / 1000)
    })
    eachTrainingSet(sessions, start, end, function(set) { summary.volume += setVolume(set) })
    summary.volume = Store.round(summary.volume, 2)
    return summary
}

// Monday of the week `date` is in, local midnight.
function weekStart(date) {
    var day = Store.addDays(date, 0)
    return Store.addDays(day, -((day.getDay() + 6) % 7))
}

// Volume per ISO week (weekly_volume_series): [{ x: <Monday ms>, value }],
// oldest first, only weeks with training.
function weeklyVolume(sessions, start, end) {
    var weeks = {}
    eachTrainingSet(sessions, start, end, function(set, pe, session) {
        var key = weekStart(new Date(session.started_at)).getTime()
        weeks[key] = (weeks[key] || 0) + setVolume(set)
    })
    return Object.keys(weeks).map(function(key) {
        return { x: Number(key), value: Store.round(weeks[key], 2) }
    }).sort(function(a, b) { return a.x - b.x })
}

// Volume per primary muscle group (muscle_group_volume_series): a set
// counts in full for each of its exercise's primary muscle groups.
// `primaryGroups` maps exercise id -> [muscle group id]. Biggest first:
// [{ id, value }].
function muscleGroupVolume(sessions, start, end, primaryGroups) {
    var totals = {}
    eachTrainingSet(sessions, start, end, function(set, pe) {
        var volume = setVolume(set)
        ;(primaryGroups[pe.exercise] || []).forEach(function(id) {
            totals[id] = (totals[id] || 0) + volume
        })
    })
    return Object.keys(totals).map(function(id) {
        return { id: Number(id), value: Store.round(totals[id], 2) }
    }).sort(function(a, b) { return b.value - a.value || a.id - b.id })
}

var PRIMARY_RECORD_TYPES = ["max_weight", "estimated_1rm", "set_volume", "session_volume"]

// Records achieved in [start, end], grouped by exercise like the web's
// pr_history_grouped_by_exercise: groups in order of each exercise's
// newest record, the headline types first and the rest (rep records)
// behind "more" - or, with no headline record, the rep records instead.
// `records` is records/ as it comes, newest first.
// [{ exercise, name, primary: [record], secondary: [record] }]
function recordGroups(records, start, end) {
    var groups = []
    var byExercise = {}
    ;(records || []).forEach(function(record) {
        var day = Store.isoDate(new Date(record.achieved_at))
        if ((start && day < Store.isoDate(start)) || (end && day > Store.isoDate(end)))
            return
        var group = byExercise[record.exercise]
        if (!group) {
            group = { exercise: record.exercise, name: record.exercise_name, primary: [], secondary: [] }
            byExercise[record.exercise] = group
            groups.push(group)
        }
        if (PRIMARY_RECORD_TYPES.indexOf(record.record_type) >= 0)
            group.primary.push(record)
        else
            group.secondary.push(record)
    })
    groups.forEach(function(group) {
        if (group.primary.length === 0) {
            group.primary = group.secondary
            group.secondary = []
        }
    })
    return groups
}

// How each measurement changed in [start, end] (body_measurement_progress):
// per active type with readings, the latest value and the change from the
// first, both in the display unit and rounded to one decimal before
// subtracting so the figures add up. No change for a single reading, no
// percent for a percentage type or a first value of 0. Body weight first,
// then by name as shown.
// [{ type, value, unit, change, changePercent }]
function bodyProgress(readings, types, start, end, unitSystem) {
    var typeById = {}
    ;(types || []).forEach(function(t) { if (t.active !== false) typeById[t.id] = t })
    var byType = {}
    ;(readings || []).slice().sort(function(a, b) {
        return new Date(a.recorded_at) - new Date(b.recorded_at)
    }).forEach(function(r) {
        var day = Store.isoDate(new Date(r.recorded_at))
        if (!typeById[r.measurement_type] || (start && day < Store.isoDate(start)) || (end && day > Store.isoDate(end)))
            return
        ;(byType[r.measurement_type] = byType[r.measurement_type] || []).push(Store.parseNumber(r.value))
    })
    var rows = Object.keys(byType).map(function(id) {
        var type = typeById[id]
        var values = byType[id]
        var display = function(v) { return Store.round(Store.measurementToDisplay(v, type.unit_kind, unitSystem), 1) }
        var latest = display(values[values.length - 1])
        var row = { type: type, value: latest, unit: Store.measurementUnit(type.unit_kind, unitSystem),
                    change: null, changePercent: null }
        if (values.length > 1) {
            row.change = Store.round(latest - display(values[0]), 1)
            if (type.unit_kind !== "percentage" && values[0])
                row.changePercent = Store.round((values[values.length - 1] - values[0]) / values[0] * 100, 1)
        }
        return row
    })
    return rows.sort(function(a, b) {
        var aw = Store.isBodyWeightType(a.type) ? 0 : 1
        var bw = Store.isBodyWeightType(b.type) ? 0 : 1
        return aw - bw || Store.contentName(a.type.name).localeCompare(Store.contentName(b.type.name))
    })
}

// "+1.5" / "-0.3" / "0".
function signed(value) {
    return (value > 0 ? "+" : "") + Store.formatNumber(value)
}

// --- body tracking reminder ---------------------------------------------------
// The web's "Time to log your body measurements?" card
// (apps.measurements.services.needs_body_tracking_reminder): 14 days or
// more since the newest reading of any type. The web counts from the day
// the account was made when there's no reading at all; the API doesn't
// say when that was, so here a reading is needed.
var BODY_TRACKING_REMINDER_DAYS = 14

function needsBodyReminder(latestRecordedAt, now) {
    if (!latestRecordedAt)
        return false
    return (now - new Date(latestRecordedAt)) / 86400000 >= BODY_TRACKING_REMINDER_DAYS
}
