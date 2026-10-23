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
}
