.pragma library
.import "db.js" as Db
.import "http.js" as Http
.import "records.js" as Records
.import "programs.js" as Programs

// Workout sessions, performed exercises and sets - IronStack's
// WorkoutSessionViewSet, PerformedExerciseViewSet and ExerciseSetViewSet
// with apps/workouts/services.py's rules: starting from a workout copies
// its prescriptions, sets are numbered one past the highest, a finished
// session can't be finished again, and every change to sets brings the
// exercise's records back in line.

var PE_TARGETS = ["set_count", "min_reps", "max_reps", "target_weight", "target_rpe", "target_rir",
                  "progression_method", "weight_increment", "notes"]

function putSession(tx, s) {
    Db.put(tx, "sessions", s, { workout: s.workout, program: s.program, status: s.status,
                                started_at: s.started_at, ended_at: s.ended_at })
}

function putPe(tx, pe) {
    Db.put(tx, "performed_exercises", pe, { session: pe.session, exercise: pe.exercise,
                                            prescription: pe.prescription, ord: pe.order })
}

function putSet(tx, s, pe) {
    Db.put(tx, "sets", s, { performed_exercise: s.performed_exercise, session: pe.session, exercise: pe.exercise,
                            set_number: s.set_number, weight: Number(s.weight), reps: s.reps,
                            is_warmup: s.is_warmup, is_failure: s.is_failure, performed_at: s.performed_at })
}

function peToApi(pe) {
    var out = {}
    for (var key in pe)
        out[key] = pe[key]
    delete out.prescription
    out.sets = Db.all("sets", "performed_exercise = ?", [pe.id], "set_number, id")
    return out
}

function sessionToApi(s) {
    s.is_in_progress = s.status === "in_progress"
    s.performed_exercises = Db.all("performed_exercises", "session = ?", [s.id], "ord, id").map(peToApi)
    return s
}

// "2026-11-04" (midnight here) or an ISO datetime, as a Date.
function boundary(value) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        var parts = value.split("-")
        return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10))
    }
    var d = new Date(value)
    return isNaN(d.getTime()) ? null : d
}

function list(match, query) {
    var where = [], args = []
    if (query.status) {
        where.push("status = ?")
        args.push(query.status)
    }
    var after = query.started_after ? boundary(query.started_after) : null
    var before = query.started_before ? boundary(query.started_before) : null
    if (after) {
        where.push("started_at >= ?")
        args.push(after.toISOString())
    }
    if (before) {
        where.push("started_at < ?")
        args.push(before.toISOString())
    }
    var clause = where.length ? " WHERE " + where.join(" AND ") : ""
    return Http.paginateQuery(Db.scalar("SELECT COUNT(*) FROM sessions" + clause, args) || 0, function(limit, offset) {
        return Db.read("SELECT data FROM sessions" + clause + " ORDER BY started_at DESC, id DESC LIMIT ? OFFSET ?",
                       args.concat([limit, offset])).map(function(row) { return sessionToApi(Db.parse(row)) })
    }, query, "sessions/")
}

function retrieve(match) {
    var s = Db.get("sessions", match[1])
    return s ? Http.ok(sessionToApi(s)) : Http.notFound()
}

// start_session: a workout's prescriptions become the session's
// performed exercises, with their targets as they are today.
function create(match, query, body) {
    body = body || {}
    var workout = null
    if (body.workout !== undefined && body.workout !== null && body.workout !== "") {
        workout = Db.get("workouts", body.workout)
        var program = workout ? Db.get("programs", workout.program) : null
        if (!workout || !program || program.active === false)
            return Http.invalid("workout", qsTranslate("Local", "Not a workout you can start."))
    }
    var id = Db.write(function(tx) {
        var session = { id: Db.nextId(tx, "sessions"), program: workout ? workout.program : null,
                        workout: workout ? workout.id : null, status: "in_progress",
                        started_at: Db.nowIso(), ended_at: null }
        putSession(tx, session)
        if (workout) {
            var ps = tx.executeSql("SELECT data FROM prescriptions WHERE parent = ? ORDER BY ord, id", [workout.id]).rows
            for (var i = 0; i < ps.length; i++) {
                var p = JSON.parse(ps.item(i).data)
                var exercise = Db.get("exercises", p.exercise)
                var pe = { id: Db.nextId(tx, "performed_exercises"), session: session.id, exercise: p.exercise,
                           exercise_name: exercise ? exercise.name : "", order: p.order, prescription: p.id }
                PE_TARGETS.forEach(function(f) { pe[f] = p[f] === undefined ? null : p[f] })
                pe.notes = p.notes || ""
                putPe(tx, pe)
            }
        }
        return session.id
    })
    return Http.created(sessionToApi(Db.get("sessions", id)))
}

function update(match, query, body) {
    var s = Db.get("sessions", match[1])
    if (!s)
        return Http.notFound()
    body = body || {}
    if (body.status !== undefined && body.status !== s.status) {
        if (["completed", "abandoned"].indexOf(body.status) < 0)
            return Http.invalid("status", qsTranslate("Local", "Not a valid choice."))
        if (s.status !== "in_progress")
            return Http.invalid("status", qsTranslate("Local", "This workout has already ended."))
        s.status = body.status
        s.ended_at = Db.nowIso()
    }
    Db.write(function(tx) { putSession(tx, s) })
    return Http.ok(sessionToApi(Db.get("sessions", s.id)))
}

function destroy(match) {
    var s = Db.get("sessions", match[1])
    if (!s)
        return Http.notFound()
    Db.write(function(tx) {
        var exercises = tx.executeSql("SELECT DISTINCT exercise FROM performed_exercises WHERE session = ?", [s.id]).rows
        tx.executeSql("DELETE FROM sets WHERE session = ?", [s.id])
        tx.executeSql("DELETE FROM performed_exercises WHERE session = ?", [s.id])
        Db.remove(tx, "sessions", s.id)
        for (var i = 0; i < exercises.length; i++)
            Records.rebuild(tx, exercises.item(i).exercise)
    })
    return Http.noContent()
}

function remainingEstimate(match) {
    var s = Db.get("sessions", match[1])
    if (!s)
        return Http.notFound()
    if (s.status !== "in_progress")
        return Http.ok({ estimate: null })
    return Http.ok({ estimate: Programs.estimateRemaining(sessionToApi(s).performed_exercises) })
}

// --- performed exercises (add_performed_exercise) -------------------------------

function createPe(match, query, body) {
    body = body || {}
    var s = Db.get("sessions", body.session)
    if (!s)
        return Http.invalid("session", qsTranslate("Local", "Not your workout session."))
    var exercise = Db.get("exercises", body.exercise)
    if (!exercise || exercise.active === false)
        return Http.invalid("exercise", qsTranslate("Local", "Not an exercise you can use."))
    var id = Db.write(function(tx) {
        var highest = tx.executeSql("SELECT MAX(ord) AS o FROM performed_exercises WHERE session = ?", [s.id]).rows.item(0).o
        var pe = { id: Db.nextId(tx, "performed_exercises"), session: s.id, exercise: exercise.id,
                   exercise_name: exercise.name, order: highest === null ? 0 : highest + 1, prescription: null,
                   set_count: null, min_reps: null, max_reps: null, target_weight: null, target_rpe: null,
                   target_rir: null, progression_method: "", weight_increment: null, notes: "" }
        putPe(tx, pe)
        return pe.id
    })
    return Http.created(peToApi(Db.get("performed_exercises", id)))
}

function getPe(match) {
    var pe = Db.get("performed_exercises", match[1])
    return pe ? Http.ok(peToApi(pe)) : Http.notFound()
}

// --- sets (log_set) ----------------------------------------------------------------

function validateSet(body) {
    if (body.weight !== undefined && (Http.num(body.weight) === null || Http.num(body.weight) < 0))
        return Http.invalid("weight", qsTranslate("Local", "A valid number is required."))
    if (body.reps !== undefined && (Http.int(body.reps) === null || Http.int(body.reps) < 0))
        return Http.invalid("reps", qsTranslate("Local", "A valid integer is required."))
    if (body.rpe !== undefined && body.rpe !== null && body.rpe !== "" && (Number(body.rpe) < 1 || Number(body.rpe) > 10))
        return Http.invalid("rpe", qsTranslate("Local", "RPE goes from 1 to 10."))
    return null
}

function applySet(s, body) {
    if (body.weight !== undefined) s.weight = Http.dec(body.weight)
    if (body.reps !== undefined) s.reps = Http.int(body.reps)
    if (body.target_reps !== undefined) s.target_reps = Http.int(body.target_reps)
    if (body.rpe !== undefined) s.rpe = Http.dec(body.rpe, 1)
    if (body.rir !== undefined) s.rir = Http.int(body.rir)
    if (body.is_failure !== undefined) s.is_failure = Http.bool(body.is_failure)
    if (body.is_warmup !== undefined) s.is_warmup = Http.bool(body.is_warmup)
    if (body.notes !== undefined) s.notes = body.notes || ""
    if (body.performed_at) s.performed_at = new Date(body.performed_at).toISOString()
}

function createSet(match, query, body) {
    body = body || {}
    var pe = Db.get("performed_exercises", body.performed_exercise)
    if (!pe)
        return Http.invalid("performed_exercise", qsTranslate("Local", "Not your workout session."))
    if (body.weight === undefined || body.reps === undefined)
        return Http.invalid(body.weight === undefined ? "weight" : "reps", qsTranslate("Local", "This field is required."))
    var error = validateSet(body)
    if (error)
        return error
    var out = Db.write(function(tx) {
        var highest = tx.executeSql("SELECT MAX(set_number) AS n FROM sets WHERE performed_exercise = ?", [pe.id]).rows.item(0).n
        var s = { id: Db.nextId(tx, "sets"), performed_exercise: pe.id, set_number: (highest || 0) + 1,
                  weight: null, reps: null, target_reps: null, rpe: null, rir: null, is_failure: false,
                  is_warmup: false, notes: "", performed_at: Db.nowIso() }
        applySet(s, body)
        putSet(tx, s, pe)
        return { set: s, added: Records.checkNewSet(tx, s, pe.exercise, pe.session) }
    })
    var result = JSON.parse(JSON.stringify(out.set))
    result.new_records = Records.newRecords(out.added)
    return Http.created(result)
}

function getSet(match) {
    var s = Db.get("sets", match[1])
    return s ? Http.ok(s) : Http.notFound()
}

function updateSet(match, query, body) {
    var s = Db.get("sets", match[1])
    if (!s)
        return Http.notFound()
    body = body || {}
    var error = validateSet(body)
    if (error)
        return error
    applySet(s, body)
    var pe = Db.get("performed_exercises", s.performed_exercise)
    Db.write(function(tx) {
        putSet(tx, s, pe)
        Records.rebuild(tx, pe.exercise)
    })
    return Http.ok(s)
}

function deleteSet(match) {
    var s = Db.get("sets", match[1])
    if (!s)
        return Http.notFound()
    var pe = Db.get("performed_exercises", s.performed_exercise)
    Db.write(function(tx) {
        Db.remove(tx, "sets", s.id)
        Records.rebuild(tx, pe.exercise)
    })
    return Http.noContent()
}

var routes = [
    ["GET", /^sessions\/$/, list],
    ["POST", /^sessions\/$/, create],
    ["GET", /^sessions\/(\d+)\/$/, retrieve],
    ["PATCH", /^sessions\/(\d+)\/$/, update],
    ["DELETE", /^sessions\/(\d+)\/$/, destroy],
    ["GET", /^sessions\/(\d+)\/remaining-estimate\/$/, remainingEstimate],
    ["POST", /^performed-exercises\/$/, createPe],
    ["GET", /^performed-exercises\/(\d+)\/$/, getPe],
    ["POST", /^sets\/$/, createSet],
    ["GET", /^sets\/(\d+)\/$/, getSet],
    ["PATCH", /^sets\/(\d+)\/$/, updateSet],
    ["PUT", /^sets\/(\d+)\/$/, updateSet],
    ["DELETE", /^sets\/(\d+)\/$/, deleteSet]
]
