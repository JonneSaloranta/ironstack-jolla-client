import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// The web's cool-down card on a finished workout: the cool-down done after
// it, or stretches picked for the muscles it trained with a button to start
// them as a guided session marked as its cool-down. Nothing without the
// stretching permission or a match.
Column {
    id: card

    // The workout session as read from the server.
    property var session: null

    // The cool-down logged for it: a stretch session, or null.
    property var done: null
    property var suggestion: null
    property var muscleNames: []
    property bool loaded: false
    property bool loading: false

    readonly property bool finished: session !== null && session.status === "completed"

    width: parent ? parent.width : 0
    visible: loaded && (done !== null || suggestion !== null)

    function load() {
        if (!finished || loaded || loading)
            return
        var exerciseIds = (session.performed_exercises || []).map(function(pe) { return pe.exercise })
        if (exerciseIds.length === 0)
            return
        loading = true
        var pending = 4
        var routines = []
        var groups = {}
        var failed = false
        function settle(ok) {
            if (!ok)
                failed = true
            if (--pending > 0)
                return
            loading = false
            if (failed)
                return
            var muscles = (Store.lookups.muscleGroups || []).filter(function(m) { return groups[m.id] })
                    .sort(function(a, b) { return a.storedName.localeCompare(b.storedName) })
            muscleNames = muscles.map(function(m) { return m.name })
            if (!done)
                suggestion = Store.suggestCooldown(muscles.map(function(m) { return m.id }), routines, Store.stretches || {})
            loaded = true
        }
        // The newest stretching sessions: a cool-down follows its workout.
        api.request("GET", "stretch-sessions/?page_size=100", null, function(ok, status, data) {
            if (ok)
                done = (data.results || []).filter(function(s) {
                    return s.after_workout === session.id && s.status !== "abandoned"
                })[0] || null
            settle(ok)
        })
        Store.fetchAll(api, "stretch-routines/?page_size=100", function(results) {
            routines = routines.concat(results.filter(function(r) { return r.active !== false }))
        }, settle)
        Store.ensureStretches(api, settle)
        Store.ensureLookups(api, function() {
            Store.fetchAll(api, "exercises/?page_size=100&ids=" + exerciseIds.join(","), function(results) {
                results.forEach(function(e) {
                    ;(e.primary_muscle_groups || []).forEach(function(g) { groups[g] = true })
                })
            }, settle)
        })
    }

    function start() {
        var s = suggestion
        if (s.routine) {
            var steps = Store.stretchSteps(s.routine.items, Store.stretches || {})
            pageStack.push(Qt.resolvedUrl("../pages/StretchPlayerPage.qml"),
                           { routine: s.routine, offlineSteps: steps, afterWorkout: session.id })
        } else {
            pageStack.push(Qt.resolvedUrl("../pages/StretchPlayerPage.qml"),
                           { stretchIds: s.stretches, name: qsTr("Cool-down"), afterWorkout: session.id })
        }
    }

    // Again, e.g. back from the player: the cool-down may be there now.
    function reload() {
        if (loading)
            return
        loaded = false
        done = null
        suggestion = null
        load()
    }

    onFinishedChanged: load()
    Component.onCompleted: load()

    SectionHeader {
        text: card.done ? qsTr("Cool-down") : qsTr("Cool down with a stretch?")
    }
    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Theme.highlightColor
        text: {
            if (card.done)
                return (card.done.name ? Store.contentName(card.done.name) : qsTr("Stretching"))
                        + " · " + (card.done.status === "completed" ? qsTr("Completed") : qsTr("In progress"))
            var s = card.suggestion
            if (!s)
                return ""
            return (s.routine ? Store.contentName(s.routine.name)
                              : s.stretches.map(function(id) { return Store.stretchName(id) }).join(", "))
                    + " · ≈ " + Store.formatMinutes(s.seconds)
        }
    }
    Label {
        visible: card.done === null
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: qsTr("Picked for the muscles you trained:") + " " + card.muscleNames.join(", ")
    }
    Button {
        visible: card.done === null
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("Start cool-down")
        onClicked: card.start()
    }
    Item {
        width: 1
        height: Theme.paddingMedium
    }
}
