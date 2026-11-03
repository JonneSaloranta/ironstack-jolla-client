import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/store.js" as Store

TestCase {
    name: "Store"

    // Stands in for Silica's PageStack: only `busy` matters.
    QtObject {
        id: fakeStack
        property bool busy: false
    }

    function test_whenIdle() {
        var runs = 0
        fakeStack.busy = false
        Store.whenIdle(fakeStack, function() { runs++ })
        compare(runs, 1)

        fakeStack.busy = true
        Store.whenIdle(fakeStack, function() { runs++ })
        compare(runs, 1)
        fakeStack.busy = false
        compare(runs, 2)
        // once only
        fakeStack.busy = true
        fakeStack.busy = false
        compare(runs, 2)
    }

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

    function test_measurementUnits() {
        compare(Store.measurementUnit("weight", "metric"), "kg")
        compare(Store.measurementUnit("length", "imperial"), "in")
        compare(Store.measurementUnit("percentage", "imperial"), "%")
        // lengths: canonical meters, shown as cm (1 decimal) or inches
        compare(Store.measurementToDisplay("0.8125", "length", "metric"), 81.3)
        compare(Store.measurementToDisplay("0.0254", "length", "imperial"), 1)
        compare(Store.displayToMeasurement("81,25", "length", "metric"), 0.8125)
        compare(Store.displayToMeasurement("32", "length", "imperial"), 0.8128)
        compare(Store.displayToMeasurement("80", "weight", "metric"), 80)
        compare(Store.displayToMeasurement("18.5", "percentage", "metric"), 18.5)
        compare(Store.formatMeasurement("0.8125", "length", "metric"), "81.3 cm")
        compare(Store.formatMeasurement("18.50", "percentage", "metric"), "18.5 %")
        compare(Store.formatMeasurement("80.00", "weight", "imperial"), "176.37 lb")
        verify(isNaN(Store.displayToMeasurement("", "weight", "metric")))
    }

    function test_distance() {
        compare(Store.metersToDistance("5000.00", "metric"), 5)
        compare(Store.metersToDistance("1609.34", "imperial"), 1)
        compare(Store.distanceToMeters("5,2", "metric"), 5200)
        compare(Store.distanceToMeters("1", "imperial"), 1609.34)
        compare(Store.formatDistance("10500", "metric"), "10.5 km")
        compare(Store.formatDistance(null, "metric"), "")
    }

    function test_durations() {
        compare(Store.parseDuration("00:45:30"), 2730)
        compare(Store.parseDuration("01:00:00.500000"), 3600)
        compare(Store.parseDuration("1 02:00:00"), 93600)
        verify(isNaN(Store.parseDuration("")))
        verify(isNaN(Store.parseDuration(null)))
        compare(Store.toDuration(2730), "00:45:30")
        compare(Store.toDuration(36000), "10:00:00")
    }

    function test_isoDateAndAddDays() {
        compare(Store.isoDate(new Date(2026, 0, 5, 23, 30)), "2026-01-05")
        compare(Store.isoDate(Store.addDays(new Date(2026, 1, 28), 1)), "2026-03-01")
        compare(Store.isoDate(Store.addDays(new Date(2026, 0, 1), -1)), "2025-12-31")
    }

    function test_rangeStart() {
        var today = new Date(2026, 10, 2)
        compare(Store.isoDate(Store.rangeStart("7d", today)), "2026-10-27")
        compare(Store.isoDate(Store.rangeStart("30d", today)), "2026-10-04")
        compare(Store.rangeStart("all", today), null)
    }

    function test_exerciseTrend() {
        var trend = Store.exerciseTrend({ session_count: 2, total_volume: "1762.50", sessions: [
            { date: "2026-10-30", estimated_one_rep_max: "65.00", weight: "55.00", reps: 5 },
            { date: "2026-10-23", estimated_one_rep_max: "61.25", weight: "52.50", reps: 5 }
        ] })
        compare(trend.sessionCount, 2)
        compare(trend.volume, 1762.5)
        compare(trend.points.length, 2)
        // oldest first
        compare(trend.points[0].y, 61.25)
        compare(trend.points[0].x, new Date(2026, 9, 23).getTime())
        compare(Store.exerciseTrend({}).points.length, 0)
    }

    function test_recordValueText() {
        compare(Store.recordValueText({ record_type: "rep_pr", value: "12.00" }, "metric", "%1 reps"), "12 reps")
        compare(Store.recordValueText({ record_type: "max_weight", value: "100.00" }, "metric", "%1 reps"), "100 kg")
    }

    function test_swapTarget() {
        compare(Store.swapTarget(3, 0, -1), -1)
        compare(Store.swapTarget(3, 0, 1), 1)
        compare(Store.swapTarget(3, 2, 1), -1)
    }

    function test_measurementStats() {
        var readings = [
            { value: "82.00", recorded_at: "2026-10-03T07:00:00Z" },
            { value: "84.00", recorded_at: "2026-10-01T07:00:00Z" },
            { value: "83.00", recorded_at: "2026-10-02T07:00:00Z" }
        ]
        var stats = Store.measurementStats(readings)
        compare(stats.count, 3)
        compare(stats.latest, 82)
        compare(stats.latestAt, "2026-10-03T07:00:00Z")
        compare(stats.first, 84)
        compare(stats.change, -2)
        compare(stats.min, 82)
        compare(stats.max, 84)
        compare(stats.average, 83)
        compare(Store.measurementStats([]), null)
    }

    function test_bmi() {
        compare(Store.bmi("80.00", "1.8000"), 24.7)
        verify(isNaN(Store.bmi("80", null)))
        verify(isNaN(Store.bmi("80", "0")))
        compare(Store.bmiCategory(18.4), "underweight")
        compare(Store.bmiCategory(18.5), "normal")
        compare(Store.bmiCategory(25), "overweight")
        compare(Store.bmiCategory(30), "obese")
        compare(Store.bmiCategory(NaN), "")
    }

    function test_isBodyWeightType() {
        verify(Store.isBodyWeightType({ name: "Body weight", owner: null }))
        verify(!Store.isBodyWeightType({ name: "Body weight", owner: 5 }))
        verify(!Store.isBodyWeightType({ name: "Waist", owner: null }))
    }

    function test_formatMinutes() {
        compare(Store.formatMinutes(4500), "1h 15min")
        compare(Store.formatMinutes(3600), "1h")
        compare(Store.formatMinutes(2700), "45min")
        compare(Store.formatMinutes(20), "<1min")
        compare(Store.formatMinutes(NaN), "")
    }

    function test_activitySummary() {
        var summary = Store.activitySummary([
            { duration: "00:30:00", distance: "5000.00", calories: null },
            { duration: "01:00:00", distance: null, calories: 400 }
        ])
        compare(summary.count, 2)
        compare(summary.duration, 5400)
        compare(summary.distance, 5000)
        compare(summary.calories, 400)
        var none = Store.activitySummary([{ duration: "00:10:00", distance: null, calories: null }])
        compare(none.distance, null)
        compare(none.calories, null)
    }

    function test_stretchSteps() {
        var stretches = { 1: { per_side: true, default_hold_seconds: 30 }, 2: { per_side: false, default_hold_seconds: 20 } }
        var items = [
            { id: 11, stretch: 2, order: 1, hold_seconds: null, sets: 1, rest_seconds: 10 },
            { id: 10, stretch: 1, order: 0, hold_seconds: 45, sets: 2, rest_seconds: 10 }
        ]
        var steps = Store.stretchSteps(items, stretches)
        compare(steps.map(function(s) { return s.kind + (s.side ? ":" + s.side : "") }),
                ["prepare:left", "hold:left", "rest:left", "hold:right", "rest:right", "hold:left",
                 "rest:left", "hold:right", "prepare", "hold"])
        compare(steps[0].seconds, 5)
        compare(steps[1].seconds, 45)
        compare(steps[7].lastOfStretch, true)
        // the item's hold falls back to the stretch's default
        compare(steps[9].seconds, 20)
        compare(Store.nextStretchStep(steps, 2), 8)
        compare(Store.nextStretchStep(steps, 8), 10)
    }

    // A guided session's snapshot: only pending stretches, the snapshot's
    // own per-side flag, and each step knows what to mark.
    function test_sessionItems() {
        var stretches = { 1: { per_side: false, default_hold_seconds: 30 } }
        var session = { performed_stretches: [
            { id: 40, stretch: 1, order: 0, per_side: true, target_hold_seconds: 20, sets: 1, rest_seconds: 0,
              status: "done" },
            { id: 41, stretch: 1, order: 1, per_side: true, target_hold_seconds: null, sets: 1, rest_seconds: 0,
              status: "pending" }
        ] }
        var steps = Store.stretchSteps(Store.sessionItems(session), stretches)
        compare(steps.map(function(s) { return s.kind + (s.side ? ":" + s.side : "") }),
                ["prepare:left", "hold:left", "hold:right"])
        compare(steps[1].seconds, 30)
        compare(steps[2].performed, 41)
        compare(Store.sessionItems(null).length, 0)
    }

    function test_weeklyStretchMinutes() {
        var today = new Date(2026, 10, 4)   // a Wednesday
        var rows = Store.weeklyStretchMinutes([
            { status: "completed", date: "2026-11-02", duration: "00:10:00" },
            { status: "completed", date: "2026-11-04", duration: "00:05:30" },
            { status: "abandoned", date: "2026-11-03", duration: "00:30:00" },
            { status: "completed", date: "2026-10-28", duration: "00:12:00" }
        ], today, 3)
        compare(rows.length, 3)
        compare(Store.isoDate(rows[2].monday), "2026-11-02")
        compare(rows[2].minutes, 16)
        compare(rows[1].minutes, 12)
        compare(rows[0].minutes, 0)
    }

    function test_stretchSummary() {
        var today = new Date(2026, 10, 4)
        var sessions = [
            { status: "completed", date: "2026-11-03", duration: "00:10:00" },
            { status: "completed", date: "2026-11-02", duration: "00:05:00" },
            { status: "completed", date: "2026-10-20", duration: "00:20:00" },
            { status: "abandoned", date: "2026-11-04", duration: "00:30:00" }
        ]
        var summary = Store.stretchSummary(sessions, today)
        compare(summary.count, 3)
        compare(summary.seconds, 2100)
        compare(summary.weekCount, 2)
        compare(summary.weekSeconds, 900)
        // nothing today yet: the streak ends yesterday
        compare(summary.streak, 2)
        compare(Store.stretchSummary([], today).streak, 0)
    }

    function test_parseDateAndIsToday() {
        var day = Store.parseDate("2026-11-02")
        compare(day.getFullYear(), 2026)
        compare(day.getMonth(), 10)
        compare(day.getDate(), 2)
        compare(day.getHours(), 0)
        verify(Store.isToday("2026-11-02", new Date(2026, 10, 2, 23, 59)))
        verify(!Store.isToday("2026-11-02", new Date(2026, 10, 3, 0, 1)))
    }

    function test_formatHoursMinutes() {
        compare(Store.formatHoursMinutes(0), "0:00")
        compare(Store.formatHoursMinutes(3900), "1:05")
    }

    function test_contentName() {
        // built-in names as the web shows them, custom names as typed
        compare(Store.contentName("Skull Crusher", "fi"), "Ojentajapunnerrus tangolla")
        compare(Store.contentName("Workout A", "fi"), "Treeni A")
        compare(Store.contentName("5x5 Strength (A/B)", "fi"), "5x5-voima (A/B)")
        compare(Store.contentName("My own lift", "fi"), "My own lift")
        compare(Store.contentName("Skull Crusher", "en"), "Skull Crusher")
        compare(Store.contentName("", "fi"), "")
        compare(Store.contentName(undefined, "fi"), undefined)
        // without a language: the device's, like the rest of the UI
        compare(Store.contentLanguage(), Qt.locale().name.split("_")[0])
        compare(Store.contentName("Skull Crusher"), Store.contentName("Skull Crusher", Store.contentLanguage()))
    }

    function test_shown() {
        compare(Store.displayField("name"), "display_name")
        compare(Store.displayField("exercise_name"), "exercise_display_name")
        compare(Store.displayField("instructions"), "display_instructions")
        // the server's display twin first
        compare(Store.shown({ name: "Workout A", display_name: "Treeni A (server)" }), "Treeni A (server)")
        compare(Store.shown({ exercise_name: "Skull Crusher", exercise_display_name: "Kallonmurskaaja" },
                            "exercise_name"), "Kallonmurskaaja")
        // no twin (IronStack #47, an older cache): the app's own translation
        compare(Store.shown({ name: "Skull Crusher" }), Store.contentName("Skull Crusher"))
        compare(Store.shown({ name: "Skull Crusher", display_name: null }), Store.contentName("Skull Crusher"))
        compare(Store.shown({ name: "My own lift", display_name: "My own lift" }), "My own lift")
        compare(Store.shown(null), "")
    }

    function set(weight, reps, warmup) {
        return { weight: weight, reps: reps, is_warmup: !!warmup }
    }

    function test_lastTime() {
        var data = { session: 2, started_at: "2026-10-02T10:00:00Z",
                     sets: [set("40.00", 5, true), set("85.00", 5)] }
        var before = Store.lastTime(data)
        compare(before.sessionId, 2)
        compare(before.startedAt, "2026-10-02T10:00:00Z")
        // warm-ups are dropped
        compare(before.sets.length, 1)
        compare(before.sets[0].weight, "85.00")
        // never done, or warm-ups only: nothing to show
        compare(Store.lastTime({ session: null, started_at: null, sets: [] }), null)
        compare(Store.lastTime({ session: 3, started_at: "x", sets: [set("20.00", 10, true)] }), null)
        compare(Store.lastTime(null), null)
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

    function test_pendingPosts() {
        var items = [
            { id: 1, method: "POST", path: "sets/", body: { reps: 5 } },
            { id: 2, method: "POST", path: "diary-entries/", body: { date: "2026-11-03", food: 5 } },
            { id: 3, method: "PATCH", path: "diary-entries/", body: { quantity: 1 } }
        ]
        var pending = Store.pendingPosts(items, "diary-entries/")
        compare(pending.length, 1)
        compare(pending[0].food, 5)
        compare(pending[0].pendingId, 2)
        // a copy: the queue's own item is left alone
        verify(items[1].body.pendingId === undefined)
        compare(Store.pendingPosts(null, "sets/").length, 0)
    }

    function test_pendingSessionEnd() {
        var items = [{ id: 1, method: "PATCH", path: "sessions/9/", body: { status: "completed" } }]
        compare(Store.pendingSessionEnd(items, 9), "completed")
        compare(Store.pendingSessionEnd(items, 10), "")
        compare(Store.pendingSessionEnd([], 9), "")
    }

    function suggestion(weight, minReps, maxReps) {
        return { weight: weight, min_reps: minReps, max_reps: maxReps, method: "linear",
                 action: "increase", confidence: "high", reason: "Hit every rep" }
    }
    property var noSuggestion: ({ weight: null, min_reps: null, max_reps: null, method: null,
                                  action: null, confidence: null, reason: null })

    function test_prefill() {
        var before = { startedAt: "2026-10-01T10:00:00Z", sets: [set("80.00", 5), set("82.50", 5)] }
        // first set: the suggestion, with the bottom of its rep range
        var p = Store.prefill(pe(1, 3, [], { target_weight: "70.00" }), before, suggestion("82.50", 5, 6))
        compare(p.source, "suggestion")
        compare(p.weightKg, "82.50")
        compare(p.reps, 5)
        // after one working set: the last set this session, suggestion or not
        p = Store.prefill(pe(1, 3, [set("81.00", 4)]), before, suggestion("82.50", 5, 6))
        compare(p.source, "set")
        compare(p.weightKg, "81.00")
        compare(p.reps, 4)
        // after warm-ups only: the first working set's default, not the warm-up
        p = Store.prefill(pe(1, 3, [set("40.00", 5, true)]), before, suggestion("82.50", 5, 6))
        compare(p.source, "suggestion")
        compare(p.weightKg, "82.50")
        // no suggested weight: the plan's target, reps from min_reps (as the web)
        p = Store.prefill(pe(1, 3, [], { target_weight: "70.00", min_reps: 6, max_reps: 8 }), before, noSuggestion)
        compare(p.source, "target")
        compare(p.weightKg, "70.00")
        compare(p.reps, 6)
        // no suggestion or target: last time's first working set
        p = Store.prefill(pe(1, 3, []), before, null)
        compare(p.source, "previous")
        compare(p.weightKg, "80.00")
        compare(p.date, "2026-10-01T10:00:00Z")
        // warm-ups only and nothing better: repeat the warm-up
        p = Store.prefill(pe(1, 3, [set("40.00", 5, true)]), null, null)
        compare(p.source, "set")
        compare(p.weightKg, "40.00")
        // nothing at all
        p = Store.prefill(pe(1, null, [], { min_reps: null, max_reps: null }), null, null)
        compare(p.source, "")
        compare(p.reps, null)
    }

    function test_suggestionText() {
        compare(Store.suggestionText(suggestion("52.50", 5, 5), "metric", "Suggested: %1"),
                "Suggested: 52.5 kg x 5")
        compare(Store.suggestionText(suggestion("40.00", 8, 12), "metric", "Suggested: %1"),
                "Suggested: 40 kg x 8-12")
        compare(Store.suggestionText(suggestion("40.00", null, null), "metric", "%1"), "40 kg")
        compare(Store.suggestionText(noSuggestion, "metric", "%1"), "")
        compare(Store.suggestionText(null, "metric", "%1"), "")
    }

    function test_targetText() {
        compare(Store.targetText(pe(1, 3, []), "metric"), "3 x 5")
        compare(Store.targetText(pe(1, 3, [], { min_reps: 8, max_reps: 12, target_weight: "40.00" }), "metric"),
                "3 x 8-12 @ 40 kg")
        compare(Store.targetText(pe(1, null, []), "metric"), "")
    }

    function test_programGroup() {
        compare(Store.programGroup({ owner: 109, is_template: false }), "own")
        compare(Store.programGroup({ owner: 109, is_template: true }), "own")
        // shared by a coach: under Coaching, not here
        compare(Store.programGroup({ owner: 115, is_template: false }, [115]), "")
        compare(Store.programGroup({ owner: 109, is_template: false }, [115]), "own")
        compare(Store.programGroup({ owner: null, is_template: true, is_system_template: true }), "template")
        // ownerless but not a template: not listed (the web page skips it too)
        compare(Store.programGroup({ owner: null, is_template: false, is_system_template: true }), "")
    }
}
