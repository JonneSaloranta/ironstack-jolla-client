import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/store.js" as Store

TestCase {
    name: "Store"

    function test_weightUnit() {
        compare(Store.weightUnit("metric"), "kg")
        compare(Store.weightUnit("imperial"), "lb")
    }

    function test_kgToDisplay() {
        compare(Store.kgToDisplay("82.50", "metric"), 82.5)
        fuzzyCompare(Store.kgToDisplay("100", "imperial"), 220.462, 0.001)
        verify(isNaN(Store.kgToDisplay("", "metric")))
    }

    function test_displayToKg() {
        compare(Store.displayToKg("82,5", "metric"), 82.5)
        compare(Store.displayToKg("82.5", "metric"), 82.5)
        // 225 lb = 102.058 kg, rounded to the API's two decimals
        compare(Store.displayToKg("225", "imperial"), 102.06)
        verify(isNaN(Store.displayToKg("abc", "metric")))
    }

    function test_roundTripImperial() {
        // A weight logged in lb must come back as the same lb figure.
        var kg = Store.displayToKg("185", "imperial")
        compare(Store.formatNumber(Math.round(Store.kgToDisplay(kg, "imperial"))), "185")
    }

    function test_formatWeight() {
        compare(Store.formatWeight("80.00", "metric"), "80 kg")
        compare(Store.formatWeight("82.50", "metric"), "82.5 kg")
        compare(Store.formatWeight(null, "metric"), "-")
        compare(Store.formatWeight("", "metric"), "-")
    }

    function test_formatDuration() {
        compare(Store.formatDuration(0), "0:00")
        compare(Store.formatDuration(65), "1:05")
        compare(Store.formatDuration(3725), "1:02:05")
        compare(Store.formatDuration(-5), "0:00")
    }

    function test_formatHoursMinutes() {
        compare(Store.formatHoursMinutes(0), "0:00")
        compare(Store.formatHoursMinutes(3900), "1:05")
    }

    function test_exerciseNameCache() {
        compare(Store.exerciseName(987654), "#987654")
        Store.rememberExercises([{ id: 987654, name: "Squat" }])
        compare(Store.exerciseName(987654), "Squat")
    }

    function session(id, status, performed) {
        return { id: id, status: status, started_at: "2026-10-0" + id + "T10:00:00Z",
                 performed_exercises: performed }
    }
    function set(weight, reps, warmup) {
        return { weight: weight, reps: reps, is_warmup: !!warmup }
    }

    function test_previousPerformance_newestCompletedWins() {
        var sessions = [
            session(3, "in_progress", [{ exercise: 7, sets: [set("90.00", 5)] }]),
            session(2, "completed", [{ exercise: 7, sets: [set("40.00", 5, true), set("85.00", 5)] }]),
            session(1, "completed", [{ exercise: 7, sets: [set("80.00", 5)] }])
        ]
        var previous = Store.previousPerformance(sessions, 7, 3)
        compare(previous.sessionId, 2)
        // warm-ups are dropped
        compare(previous.sets.length, 1)
        compare(previous.sets[0].weight, "85.00")
    }

    function test_previousPerformance_skipsCurrentAbandonedAndEmpty() {
        var sessions = [
            session(4, "completed", [{ exercise: 7, sets: [set("99.00", 1)] }]),
            session(3, "abandoned", [{ exercise: 7, sets: [set("95.00", 5)] }]),
            session(2, "completed", [{ exercise: 7, sets: [set("20.00", 10, true)] }]),
            session(1, "completed", [{ exercise: 9, sets: [set("60.00", 8)] }])
        ]
        compare(Store.previousPerformance(sessions, 7, 4), null)
        compare(Store.previousPerformance(sessions, 9, 4).sessionId, 1)
        compare(Store.previousPerformance([], 9, 4), null)
    }

    function test_summarizeSets() {
        compare(Store.summarizeSets([set("80.00", 5), set("80.00", 5), set("80.00", 5)], "metric"),
                "3 x 5 @ 80 kg")
        compare(Store.summarizeSets([set("80.00", 5), set("75.00", 6)], "metric"),
                "80 kg x 5, 75 kg x 6")
        compare(Store.summarizeSets([], "metric"), "")
    }

    function test_recordLabel() {
        compare(Store.recordLabel({ record_type_display: "Rep-specific PR", rep_count: 5 }, "%1RM"),
                "Rep-specific PR (5RM)")
        compare(Store.recordLabel({ record_type_display: "Max weight", rep_count: null }, "%1RM"),
                "Max weight")
    }

    function pe(id, setCount, sets, extra) {
        var result = { id: id, exercise: id * 10, exercise_name: "E" + id, set_count: setCount,
                       min_reps: 5, max_reps: 5, target_weight: null, sets: sets || [] }
        for (var key in extra || {})
            result[key] = extra[key]
        return result
    }

    function test_isExerciseComplete() {
        verify(!Store.isExerciseComplete(pe(1, 3, [set("50", 5), set("50", 5)])))
        verify(Store.isExerciseComplete(pe(1, 2, [set("50", 5), set("50", 5)])))
        // warm-ups don't count towards the target
        verify(!Store.isExerciseComplete(pe(1, 2, [set("20", 5, true), set("50", 5)])))
        // freeform: done after any set
        verify(!Store.isExerciseComplete(pe(1, null, [])))
        verify(Store.isExerciseComplete(pe(1, null, [set("20", 5, true)])))
    }

    function test_firstIncompleteIndex() {
        var done = pe(1, 1, [set("50", 5)])
        compare(Store.firstIncompleteIndex([done, pe(2, 3, []), pe(3, 3, [])]), 1)
        compare(Store.firstIncompleteIndex([done, done]), -1)
        compare(Store.firstIncompleteIndex([]), -1)
    }

    function test_mergePendingSets() {
        var session = { id: 9, performed_exercises: [
            pe(1, 3, [{ id: 100, set_number: 1, weight: "50.00", reps: 5, is_warmup: false }]),
            pe(2, 3, [])
        ] }
        var items = [
            { id: 4, method: "POST", path: "sets/", body: { performed_exercise: 1, weight: 52.5, reps: 5 } },
            { id: 5, method: "POST", path: "sets/", body: { performed_exercise: 2, weight: 40, reps: 8 } },
            { id: 6, method: "PATCH", path: "sessions/9/", body: { status: "completed" } }
        ]
        var merged = Store.mergePendingSets(session, items)
        compare(merged[0].sets.length, 2)
        compare(merged[0].sets[1].pending, true)
        compare(merged[0].sets[1].set_number, 2)
        compare(merged[0].sets[1].weight, 52.5)
        compare(merged[1].sets[0].set_number, 1)
        // the server's data is not modified
        compare(session.performed_exercises[0].sets.length, 1)
        compare(Store.mergePendingSets(null, items).length, 0)
    }

    function test_pendingSessionEnd() {
        var items = [{ id: 1, method: "PATCH", path: "sessions/9/", body: { status: "completed" } }]
        compare(Store.pendingSessionEnd(items, 9), "completed")
        compare(Store.pendingSessionEnd(items, 10), "")
        compare(Store.pendingSessionEnd([], 9), "")
    }

    function test_prefill() {
        var before = { startedAt: "2026-10-01T10:00:00Z", sets: [set("80.00", 5), set("82.50", 5)] }
        // nothing logged yet: last time's first set
        var p = Store.prefill(pe(1, 3, []), before)
        compare(p.source, "previous")
        compare(p.weightKg, "80.00")
        // after one working set: the last set this session
        p = Store.prefill(pe(1, 3, [set("81.00", 4)]), before)
        compare(p.source, "set")
        compare(p.weightKg, "81.00")
        compare(p.reps, 4)
        // after warm-ups only: last time's first working set, not the warm-up
        p = Store.prefill(pe(1, 3, [set("40.00", 5, true)]), before)
        compare(p.source, "previous")
        compare(p.weightKg, "80.00")
        // no history: the plan's target
        p = Store.prefill(pe(1, 3, [], { target_weight: "70.00", max_reps: 6 }), null)
        compare(p.source, "target")
        compare(p.weightKg, "70.00")
        compare(p.reps, 6)
        // nothing at all
        p = Store.prefill(pe(1, null, [], { min_reps: null, max_reps: null }), null)
        compare(p.source, "")
        compare(p.reps, null)
    }

    function test_targetText() {
        compare(Store.targetText(pe(1, 3, []), "metric"), "3 x 5")
        compare(Store.targetText(pe(1, 3, [], { min_reps: 8, max_reps: 12, target_weight: "40.00" }), "metric"),
                "3 x 8-12 @ 40 kg")
        compare(Store.targetText(pe(1, null, []), "metric"), "")
    }
}
