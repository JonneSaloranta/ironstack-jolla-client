import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// The web's cool-down card on a finished workout: the cool-down done after
// it, or the server's pick of stretches for the muscles it trained, with a
// button to start them as a guided session marked as its cool-down.
// Nothing without the stretching permission or a match.
Column {
    id: card

    // The workout session as read from the server.
    property var session: null

    // The cool-down started or done after it: a stretch session, or null.
    property var done: null
    // { routine, stretches, seconds }, or null when nothing matches.
    property var suggestion: null
    property var muscleNames: []
    property bool loaded: false
    property bool loading: false

    readonly property bool finished: session !== null && session.status === "completed"

    width: parent ? parent.width : 0
    visible: loaded && (done !== null || suggestion !== null)

    // The server's suggestion (sessions/<id>/cooldown/, the web's card).
    // A key without the stretching permission gets a 403: no card.
    function load() {
        if (!finished || loaded || loading)
            return
        loading = true
        api.request("GET", "sessions/" + session.id + "/cooldown/", null, function(ok, status, data) {
            loading = false
            if (!ok)
                return
            done = data.done || null
            muscleNames = (data.muscle_groups || []).map(function(m) {
                return Store.shown(m)
            })
            var stretches = data.stretches || []
            if (!done && (data.routine || stretches.length > 0))
                suggestion = { routine: data.routine || null, stretches: stretches, seconds: data.planned_seconds || 0 }
            loaded = true
        })
    }

    function start() {
        var s = suggestion
        Store.ensureStretches(api, function() {
            if (s.routine) {
                var steps = Store.stretchSteps(s.routine.items, Store.stretches || {})
                pageStack.push(Qt.resolvedUrl("../pages/StretchPlayerPage.qml"),
                               { routine: s.routine, offlineSteps: steps, afterWorkout: session.id })
            } else {
                pageStack.push(Qt.resolvedUrl("../pages/StretchPlayerPage.qml"),
                               { stretchIds: s.stretches.map(function(st) { return st.id }),
                                 name: qsTr("Cool-down"), afterWorkout: session.id })
            }
        })
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
                return (card.done.name ? Store.shown(card.done) : qsTr("Stretching"))
                        + " · " + (card.done.status === "completed" ? qsTr("Completed") : qsTr("In progress"))
            var s = card.suggestion
            if (!s)
                return ""
            return (s.routine ? Store.shown(s.routine)
                              : s.stretches.map(function(st) {
                                  return Store.shown(st)
                              }).join(", "))
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
