import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/local/db.js" as Db
import "../../qml/js/local/seed.js" as Seed

// The standalone mode's database (docs/STANDALONE.md): its schema, ids
// and how IronStack's built-in content is brought in and kept current.
TestCase {
    name: "LocalDb"

    function seedText(version, exercises) {
        return JSON.stringify({
            version: version, muscle_groups: [{ id: 1, name: "Chest", builtin_key: "Chest" }], equipment: [],
            exercises: exercises, programs: []
        })
    }

    function exercise(id, name) {
        return { id: id, name: name, builtin_key: name, active: true, images: [], primary_muscle_groups: [1],
                 secondary_muscle_groups: [], equipment: null, movement_type: "compound",
                 weight_input_mode: "total", description: "", instructions: "", instructions_attribution: "" }
    }

    function init() {
        Db.open("ironstack-test-db")
        Db.reset()
    }

    function test_schema() {
        compare(Db.meta("schema_version"), String(Db.MIGRATIONS.length))
        // Opening again runs nothing twice.
        Db.open("ironstack-test-db")
        compare(Db.meta("schema_version"), String(Db.MIGRATIONS.length))
    }

    function test_userIds() {
        var id = Db.write(function(tx) { return Db.nextId(tx, "exercises") })
        compare(id, Db.FIRST_USER_ID)
        Db.write(function(tx) { Db.put(tx, "exercises", { id: id, name: "Mine" }, { owner: 1 }) })
        compare(Db.write(function(tx) { return Db.nextId(tx, "exercises") }), Db.FIRST_USER_ID + 1)
        compare(Db.get("exercises", id).name, "Mine")
        compare(Db.get("exercises", "nonsense"), null)
    }

    function test_seed() {
        verify(Seed.apply(seedText("a", [exercise(1, "Squat"), exercise(2, "Bench")])))
        compare(Db.all("exercises").length, 2)
        // The same version again changes nothing.
        verify(!Seed.apply(seedText("a", [])))
        compare(Db.all("exercises").length, 2)
        // A newer one: a renamed built-in is updated, a dropped one stays
        // (history refers to it) but inactive; the user's rows are left alone.
        Db.write(function(tx) { Db.put(tx, "exercises", { id: Db.FIRST_USER_ID, name: "Mine", owner: 1 }, { owner: 1 }) })
        verify(Seed.apply(seedText("b", [exercise(1, "Back Squat")])))
        compare(Db.get("exercises", 1).name, "Back Squat")
        compare(Db.get("exercises", 2).active, false)
        compare(Db.get("exercises", Db.FIRST_USER_ID).name, "Mine")
    }

    function test_clock() {
        Db.setClock(function() { return new Date(Date.UTC(2026, 0, 2, 3, 4, 5)) })
        compare(Db.nowIso(), "2026-01-02T03:04:05.000Z")
        Db.setClock(null)
        verify(Math.abs(Db.now() - new Date()) < 5000)
    }
}
