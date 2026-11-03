.pragma library
// The web's Progress page (apps/analytics/services.py): the analytics
// endpoints' answers in the page's shapes, and what the API leaves to the
// client - records grouped by exercise and how each body measurement
// changed. Pure functions; the page fetches.
// Weights and volumes stay canonical kg here, the page converts.
.import "store.js" as Store

// analytics/summary/: workouts, training time (seconds) and volume (kg).
function summaryFrom(data) {
    return {
        sessionCount: (data && data.session_count) || 0,
        duration: (data && data.total_duration_seconds) || 0,
        volume: data ? Store.parseNumber(data.total_volume) || 0 : 0
    }
}

// analytics/volume/: [{ x: <Monday ms>, value }], oldest first, only
// weeks with training.
function weeklyFrom(data) {
    return ((data && data.weeks) || []).map(function(w) {
        return { x: Store.parseDate(w.week_start).getTime(), value: Store.parseNumber(w.volume) || 0 }
    }).sort(function(a, b) { return a.x - b.x })
}

// analytics/muscle-groups/: [{ id, name, value }], biggest first; the
// name translated like the web's.
function musclesFrom(data) {
    return ((data && data.muscle_groups) || []).map(function(m) {
        return { id: m.muscle_group, name: Store.contentName(m.muscle_group_name),
                 value: Store.parseNumber(m.volume) || 0 }
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
