import QtQuick 2.0
import QtTest 1.0
import "../../qml/js/local/db.js" as Db
import "../../qml/js/local/router.js" as Router
import "../../qml/js/local/sessions.js" as Sessions
import "../../qml/js/local/records.js" as Records

// Years of training on the phone (docs/STANDALONE.md): 1200 sessions of
// 25 sets, about five years at five a week. The calls a page makes must
// stay well under a second on the build engine; a phone is slower.
TestCase {
    name: "LocalPerf"

    function readSeed() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", Qt.resolvedUrl("../../qml/data/seed.json"), false)
        xhr.send()
        return xhr.responseText
    }

    function timed(label, budgetMs, fn) {
        var start = Date.now()
        var result = fn()
        var ms = Date.now() - start
        console.log(label + ": " + ms + " ms")
        verify(ms < budgetMs, label + " took " + ms + " ms")
        return result
    }

    function initTestCase() {
        Router.init(readSeed(), "", "ironstack-test-perf")
        Db.reset()
        Router.init(readSeed(), "", "ironstack-test-perf")
        var exercises = [1, 2, 3, 4, 5]
        var start = new Date(2021, 0, 1, 18, 0, 0).getTime()
        timed("30000 sets inserted", 60000, function() { Db.write(function(tx) {
            var setId = 100001, peId = 100001
            for (var i = 0; i < 1200; i++) {
                var started = new Date(start + i * 36 * 3600000)
                var session = { id: 100001 + i, program: null, workout: null, status: "completed",
                                started_at: started.toISOString(),
                                ended_at: new Date(started.getTime() + 3600000).toISOString() }
                Sessions.putSession(tx, session)
                for (var e = 0; e < exercises.length; e++) {
                    var pe = { id: peId++, session: session.id, exercise: exercises[e], exercise_name: "",
                               order: e, prescription: null, set_count: 5, min_reps: 5, max_reps: 5 }
                    Sessions.putPe(tx, pe)
                    for (var n = 1; n <= 5; n++) {
                        Sessions.putSet(tx, { id: setId++, performed_exercise: pe.id, set_number: n,
                                              weight: (40 + i * 0.05).toFixed(2), reps: 5, is_warmup: false,
                                              is_failure: false, performed_at: new Date(started.getTime() + (e * 5 + n) * 120000).toISOString() }, pe)
                    }
                }
            }
        }) })
        timed("records rebuild, 5 exercises", 20000, function() {
            Db.write(function(tx) { exercises.forEach(function(e) { Records.rebuild(tx, e) }) })
        })
    }

    function test_calls() {
        compare(Db.scalar("SELECT COUNT(*) FROM sets"), 30000)
        timed("summary all", 1000, function() { return Router.handle("GET", "analytics/summary/?range=all", null) })
        timed("volume 1y", 1000, function() { return Router.handle("GET", "analytics/volume/?range=1y", null) })
        timed("exercise trend all", 1000, function() { return Router.handle("GET", "analytics/exercises/1/?range=all", null) })
        timed("records page", 500, function() { return Router.handle("GET", "records/?page_size=100", null) })
        timed("last performance", 200, function() { return Router.handle("GET", "exercises/1/last-performance/", null) })
        timed("sessions page", 500, function() { return Router.handle("GET", "sessions/?page_size=25", null) })
        timed("achievements", 1000, function() { return Router.handle("GET", "analytics/achievements/", null) })
        var session = Router.handle("POST", "sessions/", {}).data
        var pe = Router.handle("POST", "performed-exercises/", { session: session.id, exercise: 1 }).data
        timed("log a set (6000 earlier sets of it)", 1000, function() {
            return Router.handle("POST", "sets/", { performed_exercise: pe.id, weight: 200, reps: 5 })
        })
    }
}
