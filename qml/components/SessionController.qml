import QtQuick 2.0
import "../js/store.js" as Store

// One workout session's state and actions, shared by the training page and
// the full session view so neither keeps its own copy of the rules.
//
// Logging a set and ending the session go through the sync queue: they
// show up immediately and reach the server when the connection allows.
// Editing or deleting a set and adding an exercise need the server right
// away (they're corrections, made from the full view).
QtObject {
    id: controller

    property int sessionId: -1
    property var session: null            // as last loaded from the server
    property string title: ""
    property bool loading: false
    property string errorText: ""
    // Showing the copy saved on the phone because the server can't be reached.
    property bool offline: false
    // exercise id -> Store.previousPerformance() result (or null)
    property var previous: ({})

    // The session's exercises with queued sets merged in.
    readonly property var exercises: Store.mergePendingSets(session, syncQueue.items)
    // "completed"/"abandoned" while ending it waits in the queue.
    readonly property string pendingEnd: Store.pendingSessionEnd(syncQueue.items, sessionId)
    readonly property bool inProgress: session !== null && session.is_in_progress && pendingEnd === ""

    signal ended(string status)

    function load() {
        loading = true
        api.request("GET", "sessions/" + sessionId + "/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                // No connection: carry on from the copy saved on the phone.
                var saved = settings.cached("session")
                if (status === 0 && saved && saved.session && saved.session.id === sessionId) {
                    offline = true
                    errorText = ""
                    if (session === null) {
                        session = saved.session
                        title = saved.title
                        previous = saved.previous || {}
                    }
                    return
                }
                errorText = error
                return
            }
            offline = false
            errorText = ""
            session = data
            if (data.is_in_progress)
                loadPrevious()
            if (data.workout) {
                api.request("GET", "workouts/" + data.workout + "/", null, function(ok2, status2, workout) {
                    if (ok2 || title === "")
                        title = ok2 ? workout.name : qsTr("Workout")
                    syncCover()
                    save()
                })
            } else {
                title = qsTr("Freeform workout")
                syncCover()
                save()
            }
        })
    }

    function save() {
        if (session && session.is_in_progress)
            settings.setCached("session", { session: session, title: title, previous: previous })
    }

    function loadPrevious() {
        Store.loadRecentSessions(api, function(sessions) {
            var map = {}
            session.performed_exercises.forEach(function(pe) {
                map[pe.exercise] = Store.previousPerformance(sessions, pe.exercise, sessionId)
            })
            previous = map
            save()
        })
    }

    function syncCover() {
        if (!session)
            return
        if (inProgress) {
            settings.activeSessionId = session.id
            settings.activeSessionName = title
            settings.activeSessionStarted = session.started_at
        } else if (settings.activeSessionId === session.id) {
            settings.clearActiveSession()
        }
    }

    function prefill(pe) {
        return Store.prefill(pe, previous[pe.exercise] || null)
    }

    // values: { weightKg, reps, rpe, rir, isWarmup, isFailure, notes }
    function logSet(pe, values) {
        syncQueue.enqueue("POST", "sets/", {
            performed_exercise: pe.id,
            target_reps: pe.max_reps || null,
            weight: values.weightKg,
            reps: values.reps,
            rpe: values.rpe === undefined ? null : values.rpe,
            rir: values.rir === undefined ? null : values.rir,
            is_warmup: !!values.isWarmup,
            is_failure: !!values.isFailure,
            notes: values.notes || ""
        })
        if (!values.isWarmup && settings.restSeconds > 0)
            settings.restEndsAt = Date.now() + settings.restSeconds * 1000
    }

    function updateSet(set, values) {
        api.request("PATCH", "sets/" + set.id + "/", {
            weight: values.weightKg,
            reps: values.reps,
            rpe: values.rpe === undefined ? null : values.rpe,
            rir: values.rir === undefined ? null : values.rir,
            is_warmup: !!values.isWarmup,
            is_failure: !!values.isFailure,
            notes: values.notes || ""
        }, afterWrite)
    }

    function deleteSet(set) {
        api.request("DELETE", "sets/" + set.id + "/", null, afterWrite)
    }

    // Adding an exercise needs its server id before sets can be logged
    // against it, so it can't wait in the queue.
    function addExercise(exerciseId) {
        api.request("POST", "performed-exercises/", { session: sessionId, exercise: exerciseId }, afterWrite)
    }

    function end(status) {
        syncQueue.enqueue("PATCH", "sessions/" + sessionId + "/", { status: status })
        settings.clearActiveSession()
        Store.invalidateRecentSessions()
        ended(status)
    }

    function afterWrite(ok, status, data, error) {
        errorText = ok ? "" : error
        load()
    }

    property Connections queueEvents: Connections {
        target: syncQueue
        onItemSynced: {
            if (path === "sets/" || path === "sessions/" + controller.sessionId + "/")
                controller.load()
        }
        onItemFailed: {
            controller.errorText = error
            controller.load()
        }
    }
}
