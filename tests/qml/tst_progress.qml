import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/progress.js" as Progress

TestCase {
    name: "Progress"

    // Local times, so the day doesn't depend on the test machine's zone.
    function at(y, m, d, h) {
        return new Date(y, m - 1, d, h || 12).toISOString()
    }

    property var sessions: [
        // Wednesday 2026-10-28
        { id: 1, status: "completed", started_at: at(2026, 10, 28, 10), ended_at: at(2026, 10, 28, 11),
          performed_exercises: [
              { exercise: 7, sets: [{ weight: "60.00", reps: 5, is_warmup: true },
                                    { weight: "100.00", reps: 5, is_warmup: false },
                                    { weight: "100.00", reps: 3, is_warmup: false, is_failure: true }] },
              { exercise: 8, sets: [{ weight: null, reps: 10, is_warmup: false }] }] },
        // Monday 2026-11-02
        { id: 2, status: "completed", started_at: at(2026, 11, 2, 10), ended_at: at(2026, 11, 2, 10, 30),
          performed_exercises: [{ exercise: 8, sets: [{ weight: "20.00", reps: 10, is_warmup: false }] }] },
        { id: 3, status: "abandoned", started_at: at(2026, 11, 2, 18), ended_at: null,
          performed_exercises: [{ exercise: 7, sets: [{ weight: "200.00", reps: 1, is_warmup: false }] }] },
        { id: 4, status: "completed", started_at: at(2026, 11, 3, 18), ended_at: null, performed_exercises: [] }
    ]

    function test_trainingSummary() {
        var s = Progress.trainingSummary(sessions, null, null)
        compare(s.sessionCount, 3)
        // warm-up and the abandoned session left out, the failed set counted
        compare(s.volume, 500 + 300 + 0 + 200)
        compare(s.duration, 3600)
        var week = Progress.trainingSummary(sessions, new Date(2026, 10, 1), new Date(2026, 10, 3))
        compare(week.sessionCount, 2)
        compare(week.volume, 200)
    }

    function test_weeklyVolume() {
        var weeks = Progress.weeklyVolume(sessions, null, null)
        compare(weeks.length, 2)
        compare(new Date(weeks[0].x).getDate(), 26)  // Monday 2026-10-26
        compare(weeks[0].value, 800)
        compare(new Date(weeks[1].x).getDate(), 2)
        compare(weeks[1].value, 200)
        // Sunday belongs to the week before
        compare(Progress.weekStart(new Date(2026, 10, 8)).getDate(), 2)
    }

    function test_muscleGroupVolume() {
        // a set counts in full for each primary group
        var groups = Progress.muscleGroupVolume(sessions, null, null, { 7: [1, 2], 8: [3] })
        compare(groups.length, 3)
        compare(groups[0].id, 1)
        compare(groups[0].value, 800)
        compare(groups[1].id, 2)
        compare(groups[2].id, 3)
        compare(groups[2].value, 200)
    }

    function test_recordGroups() {
        var records = [
            { exercise: 7, exercise_name: "Squat", record_type: "rep_specific_pr", achieved_at: at(2026, 11, 2) },
            { exercise: 8, exercise_name: "Row", record_type: "rep_pr", achieved_at: at(2026, 11, 1) },
            { exercise: 7, exercise_name: "Squat", record_type: "max_weight", achieved_at: at(2026, 11, 1) },
            { exercise: 9, exercise_name: "Old", record_type: "max_weight", achieved_at: at(2026, 1, 1) }
        ]
        var groups = Progress.recordGroups(records, new Date(2026, 9, 1), new Date(2026, 10, 3))
        compare(groups.length, 2)
        compare(groups[0].name, "Squat")
        compare(groups[0].primary.length, 1)
        compare(groups[0].primary[0].record_type, "max_weight")
        compare(groups[0].secondary.length, 1)
        // only rep records: they become the headline
        compare(groups[1].primary.length, 1)
        compare(groups[1].secondary.length, 0)
    }

    function test_bodyProgress() {
        var types = [{ id: 1, name: "Waist", unit_kind: "length", owner: null, active: true },
                     { id: 2, name: "Body weight", unit_kind: "weight", owner: null, active: true },
                     { id: 3, name: "Body fat", unit_kind: "percentage", owner: null, active: true },
                     { id: 4, name: "Old", unit_kind: "weight", owner: 5, active: false }]
        var readings = [{ measurement_type: 2, value: "81.00", recorded_at: at(2026, 11, 2) },
                        { measurement_type: 2, value: "80.00", recorded_at: at(2026, 10, 2) },
                        { measurement_type: 2, value: "90.00", recorded_at: at(2026, 1, 2) },
                        { measurement_type: 1, value: "0.8125", recorded_at: at(2026, 10, 20) },
                        { measurement_type: 3, value: "20.0", recorded_at: at(2026, 10, 1) },
                        { measurement_type: 3, value: "19.0", recorded_at: at(2026, 10, 30) },
                        { measurement_type: 4, value: "1", recorded_at: at(2026, 10, 30) }]
        var rows = Progress.bodyProgress(readings, types, new Date(2026, 9, 1), new Date(2026, 10, 3), "metric")
        compare(rows.length, 3)
        compare(rows[0].type.id, 2)  // body weight first
        compare(rows[0].value, 81)
        compare(rows[0].change, 1)
        compare(rows[0].changePercent, 1.3)
        compare(rows[1].type.id, 3)  // then by name
        compare(rows[1].change, -1)
        compare(rows[1].changePercent, null)  // a percentage has no percent change
        compare(rows[2].value, 81.3)
        compare(rows[2].unit, "cm")
        compare(rows[2].change, null)  // one reading
        compare(Progress.signed(1.5), "+1.5")
        compare(Progress.signed(-0.3), "-0.3")
    }

    function test_bodyReminder() {
        var now = new Date(2026, 10, 15, 12)
        verify(Progress.needsBodyReminder(new Date(2026, 10, 1, 12).toISOString(), now))
        verify(!Progress.needsBodyReminder(new Date(2026, 10, 1, 13).toISOString(), now))
        verify(!Progress.needsBodyReminder(null, now))
    }
}
