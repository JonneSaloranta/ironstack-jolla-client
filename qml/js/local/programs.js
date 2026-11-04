.pragma library
.import "db.js" as Db
.import "http.js" as Http

// Programs, workouts and prescriptions (IronStack's ProgramViewSet,
// WorkoutViewSet, ExercisePrescriptionViewSet), program copies, up-next
// and duration estimates.

var OWNER = 1

// --- duration estimates (apps/workouts/set_timing.py) ------------------------
// Without other users' set timings to learn from, always the default
// formula - so always "rough", as the server says when it lacks data.

var DEFAULT_CYCLE_BASE_SECONDS = 120
var DEFAULT_SECONDS_PER_REP = 3
var DEFAULT_TRANSITION_SECONDS = 180
var DEFAULT_LOW_FACTOR = 0.75
var DEFAULT_HIGH_FACTOR = 1.3
var DEFAULT_REPS = 10

function typicalReps(minReps, maxReps) {
    if (minReps && maxReps)
        return Math.round((minReps + maxReps) / 2)
    return minReps || maxReps || DEFAULT_REPS
}

function cycleSeconds(reps) {
    return DEFAULT_CYCLE_BASE_SECONDS + DEFAULT_SECONDS_PER_REP * (reps || DEFAULT_REPS)
}

// parts: [count, seconds] pairs -> {low, high, rough} or null.
function sumParts(parts) {
    parts = parts.filter(function(part) { return part[0] > 0 })
    if (!parts.length)
        return null
    var total = parts.reduce(function(sum, part) { return sum + part[0] * part[1] }, 0)
    return { low: Math.round(total * DEFAULT_LOW_FACTOR), high: Math.round(total * DEFAULT_HIGH_FACTOR), rough: true }
}

function exerciseParts(setCount, minReps, maxReps) {
    if (!setCount)
        return []
    return [[1, DEFAULT_TRANSITION_SECONDS], [setCount - 1, cycleSeconds(typicalReps(minReps, maxReps))]]
}

function estimateWorkout(prescriptions) {
    var parts = []
    prescriptions.forEach(function(p) {
        parts = parts.concat(exerciseParts(p.set_count, p.min_reps, p.max_reps))
    })
    return sumParts(parts)
}

// estimate_remaining: performed exercises with their sets.
function estimateRemaining(performedExercises) {
    var parts = []
    performedExercises.forEach(function(pe) {
        var sets = pe.sets || []
        var remaining = pe.set_count ? Math.max(pe.set_count - sets.length, 0) : (sets.length ? 0 : 1)
        if (!remaining)
            return
        var reps = typicalReps(pe.min_reps, pe.max_reps)
        if (!(pe.min_reps || pe.max_reps) && sets.length)
            reps = sets[sets.length - 1].reps
        if (sets.length) {
            parts.push([remaining, cycleSeconds(reps)])
        } else {
            parts.push([1, DEFAULT_TRANSITION_SECONDS])
            parts.push([remaining - 1, cycleSeconds(reps)])
        }
    })
    return sumParts(parts)
}

// --- serializing ----------------------------------------------------------------

function exerciseName(id) {
    var row = Db.get("exercises", id)
    return row ? row.name : ""
}

function prescriptionsOf(workoutId) {
    return Db.all("prescriptions", "parent = ?", [workoutId], "ord, id").map(function(p) {
        p.exercise_name = exerciseName(p.exercise)
        return p
    })
}

function workoutToApi(workout) {
    workout.prescriptions = prescriptionsOf(workout.id)
    workout.estimate = estimateWorkout(workout.prescriptions)
    return workout
}

function programToApi(program) {
    program.is_system_template = program.owner === null || program.owner === undefined
    if (program.is_system_template)
        program.is_template = true
    delete program.builtin_key
    program.workouts = Db.all("workouts", "parent = ?", [program.id], "ord, id").map(workoutToApi)
    return program
}

function isOwn(row) {
    return row && row.owner !== null && row.owner !== undefined
}

function forbidden() {
    return { status: 403, data: { detail: qsTranslate("Local", "Built-in templates can't be changed - copy one first.") } }
}

// Editing a program makes it a newer version (IronStack #46).
function bump(tx, programId) {
    var program = Db.get("programs", programId)
    if (!program)
        return
    program.version = (program.version || 1) + 1
    Db.put(tx, "programs", program, { owner: OWNER, active: true })
}

// One past the highest `order` under `parent` (0 for the first).
function nextOrder(tx, table, parent) {
    var highest = tx.executeSql("SELECT MAX(ord) AS o FROM " + table + " WHERE parent = ?", [parent]).rows.item(0).o
    return highest === null ? 0 : highest + 1
}

function putWorkout(tx, workout) {
    Db.put(tx, "workouts", workout, { owner: OWNER, parent: workout.program, ord: workout.order })
}

function putPrescription(tx, p) {
    Db.put(tx, "prescriptions", p, { owner: OWNER, parent: p.workout, ord: p.order, exercise: p.exercise })
}

// --- programs --------------------------------------------------------------------

function listPrograms(match, query) {
    var rows = Db.all("programs", "active = 1", [], "id").map(programToApi)
    rows.sort(function(a, b) { return a.name.localeCompare(b.name) || a.id - b.id })
    return Http.paginate(rows, query, "programs/")
}

function getProgram(match) {
    var row = Db.get("programs", match[1])
    return row && row.active !== false ? Http.ok(programToApi(row)) : Http.notFound()
}

function createProgram(match, query, body) {
    body = body || {}
    if (!body.name || !String(body.name).trim())
        return Http.invalid("name", qsTranslate("Local", "This field may not be blank."))
    var id = Db.write(function(tx) {
        var row = { id: Db.nextId(tx, "programs"), name: String(body.name).trim(), description: body.description || "",
                    is_continuous: Http.bool(body.is_continuous), is_template: Http.bool(body.is_template),
                    version: 1, owner: OWNER, active: true }
        Db.put(tx, "programs", row, { owner: OWNER, active: true })
        return row.id
    })
    return Http.created(programToApi(Db.get("programs", id)))
}

function updateProgram(match, query, body) {
    var row = Db.get("programs", match[1])
    if (!row || row.active === false)
        return Http.notFound()
    if (!isOwn(row))
        return forbidden()
    body = body || {}
    if (body.name !== undefined && !String(body.name).trim())
        return Http.invalid("name", qsTranslate("Local", "This field may not be blank."))
    ;["name", "description"].forEach(function(f) { if (body[f] !== undefined) row[f] = f === "name" ? String(body[f]).trim() : body[f] })
    ;["is_continuous", "is_template"].forEach(function(f) { if (body[f] !== undefined) row[f] = Http.bool(body[f]) })
    row.version = (row.version || 1) + 1
    Db.write(function(tx) { Db.put(tx, "programs", row, { owner: OWNER, active: true }) })
    return Http.ok(programToApi(Db.get("programs", row.id)))
}

function deleteProgram(match) {
    var row = Db.get("programs", match[1])
    if (!row || row.active === false)
        return Http.notFound()
    if (!isOwn(row))
        return forbidden()
    Db.write(function(tx) {
        var workouts = tx.executeSql("SELECT id FROM workouts WHERE parent = ?", [row.id]).rows
        for (var i = 0; i < workouts.length; i++)
            deleteWorkoutRows(tx, workouts.item(i).id)
        Db.remove(tx, "programs", row.id)
        // Sessions keep what they logged, without the program (SET_NULL).
        detachSessions(tx, "program", row.id)
    })
    return Http.noContent()
}

function detachSessions(tx, column, id) {
    var rows = tx.executeSql("SELECT id, data FROM sessions WHERE " + column + " = ?", [id]).rows
    for (var i = 0; i < rows.length; i++) {
        var session = JSON.parse(rows.item(i).data)
        session[column] = null
        if (column === "program")
            session.workout = null
        Db.put(tx, "sessions", session, { workout: session.workout, program: session.program, status: session.status,
                                          started_at: session.started_at, ended_at: session.ended_at })
    }
}

function copyProgram(match) {
    var source = Db.get("programs", match[1])
    if (!source || source.active === false)
        return Http.notFound()
    var id = Db.write(function(tx) {
        var copy = { id: Db.nextId(tx, "programs"), name: source.name, description: source.description || "",
                     is_continuous: !!source.is_continuous, is_template: false, version: 1, owner: OWNER, active: true }
        Db.put(tx, "programs", copy, { owner: OWNER, active: true })
        var workouts = tx.executeSql("SELECT data FROM workouts WHERE parent = ? ORDER BY ord, id", [source.id]).rows
        for (var i = 0; i < workouts.length; i++) {
            var workout = JSON.parse(workouts.item(i).data)
            var oldId = workout.id
            workout.id = Db.nextId(tx, "workouts")
            workout.program = copy.id
            putWorkout(tx, workout)
            var ps = tx.executeSql("SELECT data FROM prescriptions WHERE parent = ? ORDER BY ord, id", [oldId]).rows
            for (var j = 0; j < ps.length; j++) {
                var p = JSON.parse(ps.item(j).data)
                p.id = Db.nextId(tx, "prescriptions")
                p.workout = workout.id
                putPrescription(tx, p)
            }
        }
        return copy.id
    })
    return Http.created(programToApi(Db.get("programs", id)))
}

// --- workouts ------------------------------------------------------------------

function getWorkout(match) {
    var row = Db.get("workouts", match[1])
    return row ? Http.ok(workoutToApi(row)) : Http.notFound()
}

function validWeekday(value) {
    return value === null || value === undefined || value === "" || (Http.int(value) >= 0 && Http.int(value) <= 6)
}

function createWorkout(match, query, body) {
    body = body || {}
    var program = Db.get("programs", body.program)
    if (!program || program.active === false)
        return Http.invalid("program", qsTranslate("Local", "Not a program you can change."))
    if (!isOwn(program))
        return forbidden()
    if (!body.name || !String(body.name).trim())
        return Http.invalid("name", qsTranslate("Local", "This field may not be blank."))
    if (!validWeekday(body.scheduled_weekday))
        return Http.invalid("scheduled_weekday", qsTranslate("Local", "Not a valid choice."))
    var id = Db.write(function(tx) {
        var order = body.order !== undefined && body.order !== null ? Http.int(body.order)
                  : nextOrder(tx, "workouts", program.id)
        var row = { id: Db.nextId(tx, "workouts"), program: program.id, name: String(body.name).trim(), order: order,
                    scheduled_weekday: Http.int(body.scheduled_weekday), notes: body.notes || "" }
        putWorkout(tx, row)
        bump(tx, program.id)
        return row.id
    })
    return Http.created(workoutToApi(Db.get("workouts", id)))
}

function updateWorkout(match, query, body) {
    var row = Db.get("workouts", match[1])
    if (!row)
        return Http.notFound()
    if (!isOwn(Db.get("programs", row.program)))
        return forbidden()
    body = body || {}
    if (body.name !== undefined && !String(body.name).trim())
        return Http.invalid("name", qsTranslate("Local", "This field may not be blank."))
    if (body.scheduled_weekday !== undefined && !validWeekday(body.scheduled_weekday))
        return Http.invalid("scheduled_weekday", qsTranslate("Local", "Not a valid choice."))
    if (body.name !== undefined) row.name = String(body.name).trim()
    if (body.notes !== undefined) row.notes = body.notes || ""
    if (body.order !== undefined) row.order = Http.int(body.order) || 0
    if (body.scheduled_weekday !== undefined) row.scheduled_weekday = Http.int(body.scheduled_weekday)
    Db.write(function(tx) { putWorkout(tx, row); bump(tx, row.program) })
    return Http.ok(workoutToApi(Db.get("workouts", row.id)))
}

function deleteWorkoutRows(tx, workoutId) {
    tx.executeSql("DELETE FROM prescriptions WHERE parent = ?", [workoutId])
    Db.remove(tx, "workouts", workoutId)
    detachSessions(tx, "workout", workoutId)
}

function deleteWorkout(match) {
    var row = Db.get("workouts", match[1])
    if (!row)
        return Http.notFound()
    if (!isOwn(Db.get("programs", row.program)))
        return forbidden()
    Db.write(function(tx) { deleteWorkoutRows(tx, row.id); bump(tx, row.program) })
    return Http.noContent()
}

// --- prescriptions ---------------------------------------------------------------

var METHODS = ["manual", "maintenance", "linear", "double_progression", "rep_range", "percentage_based", "rpe_rir"]

function applyPrescription(row, body) {
    if (body.exercise !== undefined) row.exercise = Http.int(body.exercise)
    ;["set_count", "min_reps", "max_reps", "target_rir"].forEach(function(f) {
        if (body[f] !== undefined) row[f] = Http.int(body[f])
    })
    ;["target_weight", "weight_increment"].forEach(function(f) {
        if (body[f] !== undefined) row[f] = Http.dec(body[f])
    })
    if (body.target_rpe !== undefined) row.target_rpe = Http.dec(body.target_rpe, 1)
    if (body.percentage_target !== undefined) row.percentage_target = Http.dec(body.percentage_target)
    if (body.progression_method !== undefined) row.progression_method = body.progression_method
    if (body.notes !== undefined) row.notes = body.notes || ""
    if (body.order !== undefined) row.order = Http.int(body.order) || 0
}

function validatePrescription(row) {
    var exercise = Db.get("exercises", row.exercise)
    if (!exercise || exercise.active === false)
        return Http.invalid("exercise", qsTranslate("Local", "Not an exercise you can use."))
    if (!(row.set_count >= 1))
        return Http.invalid("set_count", qsTranslate("Local", "Ensure this value is greater than or equal to 1."))
    if (row.min_reps && row.max_reps && row.min_reps > row.max_reps)
        return Http.invalid("max_reps", qsTranslate("Local", "Max reps can't be below min reps."))
    if (METHODS.indexOf(row.progression_method) < 0)
        return Http.invalid("progression_method", qsTranslate("Local", "Not a valid choice."))
    if (row.target_rpe !== null && row.target_rpe !== undefined && (Number(row.target_rpe) < 1 || Number(row.target_rpe) > 10))
        return Http.invalid("target_rpe", qsTranslate("Local", "RPE goes from 1 to 10."))
    return null
}

function createPrescription(match, query, body) {
    body = body || {}
    var workout = Db.get("workouts", body.workout)
    if (!workout)
        return Http.invalid("workout", qsTranslate("Local", "Not a workout you can change."))
    if (!isOwn(Db.get("programs", workout.program)))
        return forbidden()
    var row = { workout: workout.id, exercise: null, order: null, set_count: 3, min_reps: null, max_reps: null,
                target_weight: null, target_rpe: null, target_rir: null, progression_method: "linear",
                weight_increment: "2.50", percentage_target: null, notes: "" }
    applyPrescription(row, body)
    var error = validatePrescription(row)
    if (error)
        return error
    var id = Db.write(function(tx) {
        if (row.order === null)
            row.order = nextOrder(tx, "prescriptions", workout.id)
        row.id = Db.nextId(tx, "prescriptions")
        putPrescription(tx, row)
        bump(tx, workout.program)
        return row.id
    })
    var created = Db.get("prescriptions", id)
    created.exercise_name = exerciseName(created.exercise)
    return Http.created(created)
}

function getPrescription(match) {
    var row = Db.get("prescriptions", match[1])
    if (!row)
        return Http.notFound()
    row.exercise_name = exerciseName(row.exercise)
    return Http.ok(row)
}

function updatePrescription(match, query, body) {
    var row = Db.get("prescriptions", match[1])
    if (!row)
        return Http.notFound()
    var workout = Db.get("workouts", row.workout)
    if (!workout || !isOwn(Db.get("programs", workout.program)))
        return forbidden()
    applyPrescription(row, body || {})
    var error = validatePrescription(row)
    if (error)
        return error
    Db.write(function(tx) { putPrescription(tx, row); bump(tx, workout.program) })
    row.exercise_name = exerciseName(row.exercise)
    return Http.ok(row)
}

function deletePrescription(match) {
    var row = Db.get("prescriptions", match[1])
    if (!row)
        return Http.notFound()
    var workout = Db.get("workouts", row.workout)
    if (!workout || !isOwn(Db.get("programs", workout.program)))
        return forbidden()
    Db.write(function(tx) { Db.remove(tx, "prescriptions", row.id); bump(tx, workout.program) })
    return Http.noContent()
}

// --- up next (apps/workouts/services.py next_workout / up_next) --------------------

function weekday(date) {
    // Python's weekday(): Monday 0 .. Sunday 6.
    return (date.getDay() + 6) % 7
}

function nextWorkout(program, today) {
    var workouts = Db.all("workouts", "parent = ?", [program.id], "ord, id")
    if (!workouts.length)
        return null
    var scheduled = workouts.filter(function(w) { return w.scheduled_weekday !== null && w.scheduled_weekday !== undefined })
    if (!program.is_continuous && scheduled.length) {
        var todayText = Http.localDate(today)
        var doneToday = Db.read("SELECT started_at FROM sessions WHERE program = ? AND status = 'completed'",
                                [program.id]).some(function(r) { return Http.localDate(r.started_at) === todayText })
        var start = doneToday ? 1 : 0
        for (var offset = start; offset < start + 7; offset++) {
            var day = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset)
            for (var i = 0; i < scheduled.length; i++) {
                if (scheduled[i].scheduled_weekday === weekday(day))
                    return { workout: scheduled[i], day: Http.localDate(day) }
            }
        }
    }
    var last = Db.scalar("SELECT workout FROM sessions WHERE program = ? AND status = 'completed' AND workout IS NOT NULL "
                         + "ORDER BY started_at DESC LIMIT 1", [program.id])
    var ids = workouts.map(function(w) { return w.id })
    var at = ids.indexOf(last)
    return { workout: at >= 0 ? workouts[(at + 1) % workouts.length] : workouts[0], day: null }
}

function upNext() {
    var empty = { program: null, workout: null, day: null }
    var programId = Db.scalar("SELECT program FROM sessions WHERE status = 'completed' AND program IS NOT NULL "
                              + "ORDER BY started_at DESC LIMIT 1")
    var program = programId ? Db.get("programs", programId) : null
    if (!program || program.active === false)
        return Http.ok(empty)
    var next = nextWorkout(program, Db.now())
    if (!next)
        return Http.ok(empty)
    return Http.ok({
        program: { id: program.id, name: program.name, is_continuous: !!program.is_continuous },
        workout: workoutToApi(next.workout),
        day: next.day
    })
}

var routes = [
    ["GET", /^programs\/$/, listPrograms],
    ["POST", /^programs\/$/, createProgram],
    ["GET", /^programs\/(\d+)\/$/, getProgram],
    ["PATCH", /^programs\/(\d+)\/$/, updateProgram],
    ["PUT", /^programs\/(\d+)\/$/, updateProgram],
    ["DELETE", /^programs\/(\d+)\/$/, deleteProgram],
    ["POST", /^programs\/(\d+)\/copy\/$/, copyProgram],
    ["GET", /^workouts\/(\d+)\/$/, getWorkout],
    ["POST", /^workouts\/$/, createWorkout],
    ["PATCH", /^workouts\/(\d+)\/$/, updateWorkout],
    ["PUT", /^workouts\/(\d+)\/$/, updateWorkout],
    ["DELETE", /^workouts\/(\d+)\/$/, deleteWorkout],
    ["POST", /^prescriptions\/$/, createPrescription],
    ["GET", /^prescriptions\/(\d+)\/$/, getPrescription],
    ["PATCH", /^prescriptions\/(\d+)\/$/, updatePrescription],
    ["PUT", /^prescriptions\/(\d+)\/$/, updatePrescription],
    ["DELETE", /^prescriptions\/(\d+)\/$/, deletePrescription],
    ["GET", /^up-next\/$/, upNext]
]
