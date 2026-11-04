.pragma library
.import "db.js" as Db
.import "http.js" as Http
.import "records.js" as Records
.import "profile.js" as Profile

// Training analytics - IronStack's apps/analytics/services.py and
// dateranges.py, and the achievement highlights for this phone's one
// user. Volume is weight x reps of working sets in completed sessions
// (a failed set still counts, a warm-up doesn't), in kg; days are this
// phone's calendar days.

var PRESET_DAYS = { "7d": 7, "30d": 30, "3m": 90, "6m": 182, "1y": 365 }

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

// dateranges.resolve: {range, start, end}, start null for all time.
function resolve(key) {
    var today = Db.now()
    var end = Http.localDate(today)
    key = key || "30d"
    if (key === "week")
        return { range: "week", start: Http.localDate(addDays(today, -((today.getDay() + 6) % 7))), end: end }
    if (PRESET_DAYS[key])
        return { range: key, start: Http.localDate(addDays(today, -PRESET_DAYS[key])), end: end }
    return { range: "all", start: null, end: end }
}

function inRange(iso, range) {
    var day = Http.localDate(iso)
    return (!range.start || day >= range.start) && day <= range.end
}

// Working sets of completed sessions in range: {weight, reps, exercise,
// session, started_at, is_failure}.
function trainingSets(range, exerciseId) {
    return Db.read("SELECT sets.weight AS weight, sets.reps AS reps, sets.exercise AS exercise, sets.session AS session, "
                   + "sets.is_failure AS is_failure, s.started_at AS started_at FROM sets "
                   + "JOIN sessions s ON s.id = sets.session WHERE s.status = 'completed' AND sets.is_warmup = 0"
                   + (exerciseId ? " AND sets.exercise = ?" : ""), exerciseId ? [exerciseId] : [])
            .filter(function(row) { return inRange(row.started_at, range) })
}

function summary(match, query) {
    var range = resolve(query.range)
    var sessions = Db.read("SELECT started_at, ended_at FROM sessions WHERE status = 'completed'")
                     .filter(function(s) { return inRange(s.started_at, range) })
    var seconds = sessions.reduce(function(sum, s) {
        return s.ended_at ? sum + (new Date(s.ended_at) - new Date(s.started_at)) / 1000 : sum
    }, 0)
    var volume = trainingSets(range).reduce(function(sum, s) { return sum + s.weight * s.reps }, 0)
    return Http.ok({ session_count: sessions.length, total_duration_seconds: seconds,
                     total_volume: Http.dec(volume), range: range })
}

function weekStart(iso) {
    var d = new Date(iso)
    return Http.localDate(addDays(d, -((d.getDay() + 6) % 7)))
}

function volume(match, query) {
    var range = resolve(query.range)
    var weeks = {}
    trainingSets(range).forEach(function(s) {
        var week = weekStart(s.started_at)
        weeks[week] = (weeks[week] || 0) + s.weight * s.reps
    })
    return Http.ok({ range: range, weeks: Object.keys(weeks).sort().map(function(week) {
        return { week_start: week, volume: Http.dec(weeks[week]) }
    }) })
}

function muscleGroups(match, query) {
    var range = resolve(query.range)
    var primary = {}
    var totals = {}
    trainingSets(range).forEach(function(s) {
        if (primary[s.exercise] === undefined) {
            var exercise = Db.get("exercises", s.exercise)
            primary[s.exercise] = exercise ? exercise.primary_muscle_groups || [] : []
        }
        primary[s.exercise].forEach(function(group) {
            totals[group] = (totals[group] || 0) + s.weight * s.reps
        })
    })
    var rows = Object.keys(totals).map(function(group) {
        var row = Db.get("muscle_groups", group)
        return { muscle_group: parseInt(group, 10), muscle_group_name: row ? row.name : "", volume: totals[group] }
    })
    rows.sort(function(a, b) { return b.volume - a.volume })
    rows.forEach(function(row) { row.volume = Http.dec(row.volume) })
    return Http.ok({ range: range, muscle_groups: rows })
}

// One exercise: sessions and volume in range, and its best set by
// estimated 1RM per training day (no failed sets, like a record).
function exercise(match, query) {
    var exerciseRow = Db.get("exercises", match[1])
    if (!exerciseRow)
        return Http.notFound()
    var range = resolve(query.range)
    var sets = trainingSets(range, exerciseRow.id)
    var sessions = {}
    var total = 0
    var best = {}
    sets.forEach(function(s) {
        sessions[s.session] = true
        total += s.weight * s.reps
        if (s.is_failure || s.reps < 1)
            return
        var day = Http.localDate(s.started_at)
        var e = Records.estimate(s.weight, s.reps)
        if (!best[day] || e > best[day].e)
            best[day] = { e: e, weight: s.weight, reps: s.reps }
    })
    return Http.ok({
        range: range, exercise: exerciseRow.id, session_count: Object.keys(sessions).length,
        total_volume: Http.dec(total),
        sessions: Object.keys(best).sort().map(function(day) {
            return { date: day, estimated_one_rep_max: Http.dec(best[day].e), weight: Http.dec(best[day].weight),
                     reps: best[day].reps }
        })
    })
}

// achievements.highlights_for, for this phone's user only.
function achievements(match, query) {
    var workouts = Db.scalar("SELECT COUNT(*) FROM sessions WHERE status = 'completed'") || 0
    if (!workouts)
        return Http.ok([])
    var days = {}
    Db.read("SELECT started_at FROM sessions WHERE status = 'completed'").forEach(function(s) {
        days[Http.localDate(s.started_at)] = true
    })
    var sorted = Object.keys(days).sort()
    var longest = 1, current = 1
    for (var i = 1; i < sorted.length; i++) {
        var gap = Math.round((new Date(sorted[i] + "T12:00:00") - new Date(sorted[i - 1] + "T12:00:00")) / 86400000)
        current = gap === 1 ? current + 1 : 1
        longest = Math.max(longest, current)
    }
    var prs = Db.scalar("SELECT COUNT(*) FROM records") || 0
    var volume = Db.scalar("SELECT SUM(sets.weight * sets.reps) FROM sets JOIN sessions s ON s.id = sets.session "
                           + "WHERE s.status = 'completed' AND sets.is_warmup = 0") || 0
    var imperial = Profile.load().unit_system === "imperial"
    var out = [
        { icon: "streak", label: qsTranslate("Achievements", "Longest streak"),
          value: qsTranslate("Achievements", "%n day(s)", "", longest), display_name: "" },
        { icon: "workouts", label: qsTranslate("Achievements", "Workouts completed"),
          value: qsTranslate("Achievements", "%n workout(s)", "", workouts), display_name: "" }
    ]
    if (prs)
        out.push({ icon: "pr", label: qsTranslate("Achievements", "Personal records"),
                   value: qsTranslate("Achievements", "%n PR(s)", "", prs), display_name: "" })
    if (volume)
        out.push({ icon: "volume", label: qsTranslate("Achievements", "Total weight lifted"),
                   value: (imperial ? (volume * 2.20462262).toFixed(2) + " lb" : volume.toFixed(2) + " kg"),
                   display_name: "" })
    return Http.ok(out)
}

var routes = [
    ["GET", /^analytics\/summary\/$/, summary],
    ["GET", /^analytics\/volume\/$/, volume],
    ["GET", /^analytics\/muscle-groups\/$/, muscleGroups],
    ["GET", /^analytics\/exercises\/(\d+)\/$/, exercise],
    ["GET", /^analytics\/achievements\/$/, achievements]
]
