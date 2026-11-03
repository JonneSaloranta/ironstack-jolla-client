import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/progress.js" as Progress

TestCase {
    name: "Progress"

    // Local times, so the day doesn't depend on the test machine's zone.
    function at(y, m, d, h) {
        return new Date(y, m - 1, d, h || 12).toISOString()
    }

    function test_fromAnalytics() {
        var summary = Progress.summaryFrom({ session_count: 2, total_duration_seconds: 997.3, total_volume: "2562.50" })
        compare(summary.sessionCount, 2)
        compare(summary.duration, 997.3)
        compare(summary.volume, 2562.5)
        compare(Progress.summaryFrom(null).sessionCount, 0)

        var weeks = Progress.weeklyFrom({ weeks: [{ week_start: "2026-10-26", volume: "200.00" },
                                                  { week_start: "2026-10-19", volume: "2562.50" }] })
        compare(weeks.length, 2)
        compare(new Date(weeks[0].x).getDate(), 19)
        compare(weeks[1].value, 200)

        var muscles = Progress.musclesFrom({ muscle_groups: [{ muscle_group: 1, muscle_group_name: "Chest", volume: "800.00" },
                                                             { muscle_group: 6, muscle_group_name: "Quads", volume: "1762.50" }] })
        compare(muscles[0].id, 6)
        compare(muscles[0].name, "Quads")
        compare(muscles[1].value, 800)
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
}
