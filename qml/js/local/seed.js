.pragma library
.import "db.js" as Db

// IronStack's built-in content (qml/data/seed.json, made by
// tools/standalone/generate_seed.py), written into the database when its
// version changes. Only built-in rows are touched; one IronStack has
// dropped stays, inactive, since history may refer to it.

var KINDS = ["muscle_groups", "equipment", "exercises"]

function apply(text) {
    if (!text)
        return false
    var seed = JSON.parse(text)
    if (Db.meta("seed_version") === seed.version)
        return false
    Db.write(function(tx) {
        KINDS.forEach(function(kind) {
            var keep = {}
            ;(seed[kind] || []).forEach(function(row) {
                keep[row.id] = true
                row.owner = null
                Db.put(tx, kind, row, { owner: null, builtin_key: row.builtin_key, active: row.active !== false })
            })
            markDropped(tx, kind, keep)
        })
        var programs = {}, workouts = {}, prescriptions = {}
        ;(seed.programs || []).forEach(function(program) {
            programs[program.id] = true
            var stored = copy(program)
            delete stored.workouts
            Db.put(tx, "programs", stored, { owner: null, builtin_key: program.builtin_key, active: true })
            program.workouts.forEach(function(workout) {
                workouts[workout.id] = true
                var w = copy(workout)
                delete w.prescriptions
                Db.put(tx, "workouts", w, { owner: null, parent: program.id, ord: workout.order })
                workout.prescriptions.forEach(function(p) {
                    prescriptions[p.id] = true
                    Db.put(tx, "prescriptions", p, { owner: null, parent: workout.id, ord: p.order,
                                                     exercise: p.exercise })
                })
            })
        })
        markDropped(tx, "programs", programs)
        Db.setMeta("seed_version", seed.version, tx)
        Db.setMeta("seed", JSON.stringify({
            // Kinds for later sections, kept until their tables exist.
            stretches: seed.stretches, stretch_routines: seed.stretch_routines,
            measurement_types: seed.measurement_types, activity_types: seed.activity_types,
            meal_slots: seed.meal_slots, foods: seed.foods, recipes: seed.recipes
        }), tx)
    })
    return true
}

function copy(object) {
    return JSON.parse(JSON.stringify(object))
}

function markDropped(tx, table, keep) {
    var rows = tx.executeSql("SELECT id, data FROM " + table + " WHERE owner IS NULL AND id < ?",
                             [Db.FIRST_USER_ID]).rows
    for (var i = 0; i < rows.length; i++) {
        var row = rows.item(i)
        if (keep[row.id])
            continue
        var data = JSON.parse(row.data)
        data.active = false
        tx.executeSql("UPDATE " + table + " SET active = 0, data = ? WHERE id = ?", [JSON.stringify(data), row.id])
    }
}
