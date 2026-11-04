import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/local/db.js" as Db
import "../../qml/js/local/router.js" as Router

// The standalone mode's backend for training (docs/STANDALONE.md),
// through the same Router.handle(method, path, body) ApiClient calls.
TestCase {
    name: "LocalTraining"

    property var clockTime: new Date(2026, 10, 2, 18, 0, 0) // Monday 2 Nov 2026, 18:00

    function readSeed() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../qml/data/seed.json"), false)
        xhr.send()
        return xhr.responseText
    }

    function call(method, path, body) {
        return Router.handle(method, path, body === undefined ? null : body)
    }

    function setNow(date) {
        clockTime = date
    }

    function advance(minutes) {
        clockTime = new Date(clockTime.getTime() + minutes * 60000)
    }

    function initTestCase() {
        Router.init(readSeed(), "file:///data", "ironstack-test-training")
        Db.setClock(function() { return clockTime })
    }

    function init() {
        Db.reset()
        Router.init(readSeed(), "file:///data", "ironstack-test-training")
        setNow(new Date(2026, 10, 2, 18, 0, 0))
    }

    // Copies the 5x5 template and returns {program, workoutA, workoutB}.
    function ownFiveByFive() {
        var templates = call("GET", "programs/?page_size=100").data.results
        var template = templates.filter(function(p) { return p.name === "5x5 Strength (A/B)" })[0]
        verify(template, "5x5 template in the seed")
        compare(template.is_system_template, true)
        var copy = call("POST", "programs/" + template.id + "/copy/")
        compare(copy.status, 201)
        compare(copy.data.is_system_template, false)
        compare(copy.data.workouts.length, 2)
        return { program: copy.data, a: copy.data.workouts[0], b: copy.data.workouts[1] }
    }

    // A session from `workout` with `sets` [[weight, reps], ...] logged
    // on its first exercise, completed.
    function trainFirst(workout, sets, failure) {
        var session = call("POST", "sessions/", { workout: workout.id }).data
        var pe = session.performed_exercises[0]
        var results = sets.map(function(s) {
            advance(2)
            return call("POST", "sets/", { performed_exercise: pe.id, weight: s[0], reps: s[1],
                                           is_failure: !!failure }).data
        })
        advance(10)
        compare(call("PATCH", "sessions/" + session.id + "/", { status: "completed" }).status, 200)
        return { session: session, pe: pe, sets: results }
    }

    function test_seed() {
        var exercises = call("GET", "exercises/?page_size=100").data
        compare(exercises.count, 28)
        compare(exercises.next, null)
        var squat = exercises.results.filter(function(e) { return e.name === "Barbell Back Squat" })[0]
        compare(squat.is_custom, false)
        compare(squat.owner, null)
        verify(squat.images[0].image.indexOf("file:///data/exercise_images/") === 0)
        compare(call("GET", "muscle-groups/").data.count, 14)
        compare(call("GET", "programs/?page_size=100").data.count, 6)
        // Applying the same seed again changes nothing.
        Router.init(readSeed(), "file:///data", "ironstack-test-training")
        compare(call("GET", "exercises/?page_size=100").data.count, 28)
    }

    function test_pagination() {
        var first = call("GET", "exercises/?page_size=10").data
        compare(first.results.length, 10)
        compare(first.count, 28)
        verify(first.next.indexOf("exercises/?") === 0)
        var second = call("GET", first.next).data
        compare(second.results.length, 10)
        verify(second.previous !== null)
        compare(call("GET", "exercises/?page=9&page_size=10").status, 404)
    }

    function test_ownExercise() {
        var created = call("POST", "exercises/", { name: " Zercher Squat ", movement_type: "compound",
                                                   weight_input_mode: "total", primary_muscle_groups: [6] })
        compare(created.status, 201)
        compare(created.data.name, "Zercher Squat")
        compare(created.data.is_custom, true)
        verify(created.data.id >= Db.FIRST_USER_ID)
        compare(call("POST", "exercises/", { name: "" }).status, 400)
        compare(call("PATCH", "exercises/1/", { name: "Mine now" }).status, 403)
        compare(call("PATCH", "exercises/" + created.data.id + "/", { name: "Zercher" }).data.name, "Zercher")
        var image = call("POST", "exercises/" + created.data.id + "/images/", { image: "file:///x.jpg", caption: "Start" })
        compare(image.status, 201)
        compare(call("GET", "exercises/" + created.data.id + "/").data.images.length, 1)
        compare(call("DELETE", "exercises/" + created.data.id + "/images/" + image.data.id + "/").status, 204)
        compare(call("DELETE", "exercises/" + created.data.id + "/").status, 204)
        // Deactivated: out of the library, still behind history.
        compare(call("GET", "exercises/" + created.data.id + "/").status, 404)
    }

    function test_templatesAreReadOnly() {
        var template = call("GET", "programs/?page_size=100").data.results[0]
        compare(call("PATCH", "programs/" + template.id + "/", { name: "x" }).status, 403)
        compare(call("POST", "workouts/", { program: template.id, name: "x" }).status, 403)
    }

    function test_editingProgram() {
        var own = ownFiveByFive()
        var workout = call("POST", "workouts/", { program: own.program.id, name: "Workout C", scheduled_weekday: 4 })
        compare(workout.status, 201)
        compare(workout.data.order, 2)
        var p = call("POST", "prescriptions/", { workout: workout.data.id, exercise: 9, set_count: 3, min_reps: 8,
                                                 max_reps: 12, progression_method: "double_progression",
                                                 weight_increment: 1 })
        compare(p.status, 201)
        compare(p.data.weight_increment, "1.00")
        compare(p.data.exercise_name, "Dumbbell Bicep Curl")
        compare(call("POST", "prescriptions/", { workout: workout.data.id, exercise: 9, set_count: 3, min_reps: 12,
                                                 max_reps: 8, progression_method: "linear" }).status, 400)
        var program = call("GET", "programs/" + own.program.id + "/").data
        compare(program.workouts.length, 3)
        verify(program.version > own.program.version)
        // 3 sets of ~10 reps: one transition and two cycles, rough.
        var estimate = program.workouts[2].estimate
        compare(estimate.rough, true)
        compare(estimate.low, Math.round((180 + 2 * 150) * 0.75))
        compare(call("DELETE", "workouts/" + workout.data.id + "/").status, 204)
        compare(call("GET", "programs/" + own.program.id + "/").data.workouts.length, 2)
    }

    function test_sessionFromWorkout() {
        var own = ownFiveByFive()
        var session = call("POST", "sessions/", { workout: own.a.id })
        compare(session.status, 201)
        compare(session.data.is_in_progress, true)
        compare(session.data.program, own.program.id)
        compare(session.data.performed_exercises.length, own.a.prescriptions.length)
        var pe = session.data.performed_exercises[0]
        compare(pe.exercise_name, own.a.prescriptions[0].exercise_name)
        compare(pe.set_count, own.a.prescriptions[0].set_count)
        compare(pe.sets.length, 0)
        compare(call("GET", "sessions/?status=in_progress").data.count, 1)

        var first = call("POST", "sets/", { performed_exercise: pe.id, weight: 60, reps: 5 })
        compare(first.status, 201)
        compare(first.data.set_number, 1)
        compare(first.data.weight, "60.00")
        // The first set is a record of every kind there is for it.
        var types = first.data.new_records.map(function(r) { return r.record_type }).sort()
        compare(types, ["estimated_1rm", "max_weight", "rep_pr", "rep_specific_pr", "rep_specific_pr",
                        "rep_specific_pr", "session_volume", "set_volume"])
        verify(first.data.new_records[0].record_type_display.length > 0)

        advance(2)
        var second = call("POST", "sets/", { performed_exercise: pe.id, weight: 60, reps: 5 })
        compare(second.data.set_number, 2)
        // A tie isn't a record; the session volume row only grows.
        compare(second.data.new_records.length, 0)
        var sessionVolume = call("GET", "records/").data.results.filter(function(r) {
            return r.record_type === "session_volume"
        })
        compare(sessionVolume.length, 1)
        compare(sessionVolume[0].value, "600.00")

        var remaining = call("GET", "sessions/" + session.data.id + "/remaining-estimate/").data.estimate
        verify(remaining.low > 0 && remaining.rough)

        compare(call("PATCH", "sessions/" + session.data.id + "/", { status: "completed" }).data.status, "completed")
        compare(call("PATCH", "sessions/" + session.data.id + "/", { status: "abandoned" }).status, 400)
        compare(call("GET", "sessions/" + session.data.id + "/remaining-estimate/").data.estimate, null)
    }

    function test_recordsFollowEdits() {
        var own = ownFiveByFive()
        var done = trainFirst(own.a, [[60, 5], [600, 5]])
        var max = function() {
            return call("GET", "records/").data.results.filter(function(r) { return r.record_type === "max_weight" })
        }
        compare(max().length, 2)
        // The 600 kg typo deleted: 60 kg is the max again (IronStack #21).
        compare(call("DELETE", "sets/" + done.sets[1].id + "/").status, 204)
        compare(max().length, 1)
        compare(max()[0].value, "60.00")
        // An edit replays too.
        compare(call("PATCH", "sets/" + done.sets[0].id + "/", { weight: 62.5 }).status, 200)
        compare(max()[0].value, "62.50")
        compare(call("DELETE", "sessions/" + done.session.id + "/").status, 204)
        compare(call("GET", "records/").data.count, 0)
    }

    function test_warmupsAndFailuresAreNoRecords() {
        var own = ownFiveByFive()
        var session = call("POST", "sessions/", { workout: own.a.id }).data
        var pe = session.performed_exercises[0]
        compare(call("POST", "sets/", { performed_exercise: pe.id, weight: 40, reps: 5, is_warmup: true })
                .data.new_records.length, 0)
        compare(call("POST", "sets/", { performed_exercise: pe.id, weight: 100, reps: 1, is_failure: true })
                .data.new_records.length, 0)
    }

    function test_lastPerformance() {
        var own = ownFiveByFive()
        var exercise = own.a.prescriptions[0].exercise
        compare(call("GET", "exercises/" + exercise + "/last-performance/").data.session, null)
        var done = trainFirst(own.a, [[60, 5], [60, 5]])
        var last = call("GET", "exercises/" + exercise + "/last-performance/").data
        compare(last.session, done.session.id)
        compare(last.sets.length, 2)
    }

    function test_linearSuggestion() {
        var own = ownFiveByFive()
        var squat = own.a.prescriptions[0] // linear, +2.5 kg, 5x5
        compare(squat.progression_method, "linear")
        var first = call("POST", "sessions/", { workout: own.a.id }).data
        var none = call("GET", "performed-exercises/" + first.performed_exercises[0].id + "/suggestion/").data
        compare(none.action, "insufficient_data")
        compare(none.confidence, "low")
        call("PATCH", "sessions/" + first.id + "/", { status: "abandoned" })

        advance(60)
        trainFirst(own.a, [[60, 5], [60, 5], [60, 5], [60, 5], [60, 5]])
        advance(60 * 24)
        var next = call("POST", "sessions/", { workout: own.a.id }).data
        var suggestion = call("GET", "performed-exercises/" + next.performed_exercises[0].id + "/suggestion/").data
        compare(suggestion.action, "increase")
        compare(suggestion.weight, "62.50")
        compare(suggestion.confidence, "medium")
        compare(suggestion.method, "linear")
        compare(suggestion.min_reps, 5)
        verify(suggestion.reason.indexOf("60.00") >= 0)
    }

    function test_linearDeload() {
        var own = ownFiveByFive()
        trainFirst(own.a, [[100, 3], [100, 3]])
        advance(60 * 24)
        trainFirst(own.a, [[100, 4], [100, 3]])
        advance(60 * 24)
        var next = call("POST", "sessions/", { workout: own.a.id }).data
        var suggestion = call("GET", "performed-exercises/" + next.performed_exercises[0].id + "/suggestion/").data
        compare(suggestion.action, "deload")
        compare(suggestion.weight, "90.00")
        compare(suggestion.confidence, "high")
    }

    function test_freeformHasNoSuggestion() {
        var session = call("POST", "sessions/", {}).data
        compare(session.workout, null)
        var pe = call("POST", "performed-exercises/", { session: session.id, exercise: 1 })
        compare(pe.status, 201)
        compare(pe.data.order, 0)
        compare(call("POST", "performed-exercises/", { session: session.id, exercise: 2 }).data.order, 1)
        var suggestion = call("GET", "performed-exercises/" + pe.data.id + "/suggestion/").data
        compare(suggestion.weight, null)
        compare(suggestion.action, null)
    }

    function test_upNext() {
        compare(call("GET", "up-next/").data.workout, null)
        var own = ownFiveByFive()
        // Monday: workout A (Monday) done today, so Wednesday's B is next.
        trainFirst(own.a, [[60, 5]])
        var next = call("GET", "up-next/").data
        compare(next.program.id, own.program.id)
        compare(next.workout.id, own.b.id)
        compare(next.day, "2026-11-04")
        verify(next.workout.estimate !== null)
    }

    function test_upNextRotation() {
        var own = ownFiveByFive()
        call("PATCH", "programs/" + own.program.id + "/", { is_continuous: true })
        trainFirst(own.a, [[60, 5]])
        var next = call("GET", "up-next/").data
        compare(next.workout.id, own.b.id)
        compare(next.day, null)
        advance(60)
        trainFirst(own.b, [[40, 5]])
        compare(call("GET", "up-next/").data.workout.id, own.a.id)
    }

    function test_analytics() {
        var own = ownFiveByFive()
        trainFirst(own.a, [[60, 5], [60, 5]]) // Monday: 600 kg
        advance(60 * 24 * 2)
        trainFirst(own.b, [[40, 5]], true) // Wednesday: a failed set still counts
        var summary = call("GET", "analytics/summary/?range=week").data
        compare(summary.session_count, 2)
        compare(summary.total_volume, "800.00")
        compare(summary.range.range, "week")
        compare(summary.range.start, "2026-11-02")
        verify(summary.total_duration_seconds > 0)

        var weeks = call("GET", "analytics/volume/?range=30d").data.weeks
        compare(weeks.length, 1)
        compare(weeks[0].week_start, "2026-11-02")
        compare(weeks[0].volume, "800.00")

        var groups = call("GET", "analytics/muscle-groups/?range=all").data.muscle_groups
        verify(groups.length >= 1)
        verify(Number(groups[0].volume) >= Number(groups[groups.length - 1].volume))

        var exercise = call("GET", "analytics/exercises/" + own.a.prescriptions[0].exercise + "/?range=all").data
        // Both 5x5 workouts start with the squat; Wednesday's set failed,
        // so only Monday has a best set.
        compare(exercise.session_count, 2)
        compare(exercise.total_volume, "800.00")
        compare(exercise.sessions.length, 1)
        compare(exercise.sessions[0].estimated_one_rep_max, "70.00")

        var achievements = call("GET", "analytics/achievements/").data
        compare(achievements[1].icon, "workouts")
        compare(achievements.length, 4)
    }

    function test_profile() {
        compare(call("GET", "profile/").data.unit_system, "metric")
        compare(call("PATCH", "profile/", { unit_system: "imperial" }).data.unit_system, "imperial")
        compare(call("GET", "profile/").data.unit_system, "imperial")
        compare(call("PATCH", "profile/", { unit_system: "stone" }).status, 400)
    }

    function test_serverOnlyAndLater() {
        compare(call("GET", "social/conversations/").status, 404)
        compare(call("GET", "assistant/").status, 404)
        var measurements = call("GET", "measurement-types/")
        compare(measurements.status, 200)
        compare(measurements.data.results.length, 0)
        compare(call("POST", "measurements/", { value: 80 }).status, 404)
    }

    function test_paths() {
        compare(call("GET", "/api/v1/exercises/1/").data.id, 1)
        compare(call("GET", "exercises/1").data.id, 1)
    }
}
