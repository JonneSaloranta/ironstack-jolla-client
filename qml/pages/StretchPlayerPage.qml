import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import QtMultimedia 5.6
import "../js/store.js" as Store

// A guided session, like the web's player: get ready, hold each stretch
// (each side, each set), rest in between, with pause and skip. IronStack
// runs the session (stretch-sessions/start/): each stretch is marked done,
// with the seconds held, or skipped as the player moves on, and the session
// is completed or abandoned at the end. One already running (started here
// or on the web) is picked up where it was. Without a connection the
// routine plays from the phone and is logged as done through the sync
// queue. Chimes like the web's timer (Settings: "Stretching timer sound"):
// a double one when a hold starts, a single one when any other step runs
// out, three at the end; skipping by hand is silent.
Page {
    id: page

    // A routine, or `stretchIds` (a cool-down's) with a `name`.
    property var routine: null
    property var stretchIds: []
    property string name: ""
    // The finished workout this is the cool-down of, or -1.
    property int afterWorkout: -1
    // The routine's steps, played when the session can't be started.
    property var offlineSteps: []

    property var session: null
    property bool offline: false
    property var steps: []
    property bool ready: false
    property int index: 0
    property bool paused: false
    property real stepEndsAt: 0
    property real remainingMs: 0
    property real activeMs: 0
    // Time spent holding the current stretch, for "done" with its seconds.
    property real heldMs: 0
    property real lastTick: 0
    property bool done: false
    property bool saving: false
    property string errorText: ""

    readonly property var step: steps[index] || null
    readonly property string title: session ? Store.contentName(session.name)
                                    : routine ? Store.contentName(routine.name) : name

    function stepTitle(kind) {
        if (kind === "prepare")
            return qsTr("Get ready")
        if (kind === "rest")
            return qsTr("Rest")
        return qsTr("Hold")
    }

    function sideText(side) {
        if (side === "left")
            return qsTr("Left side")
        if (side === "right")
            return qsTr("Right side")
        return ""
    }

    function chime(sound) {
        if (settings.timerSound)
            sound.play()
    }

    function begin() {
        saving = true
        var body = routine ? { routine: routine.id } : { stretches: stretchIds, name: name }
        if (afterWorkout >= 0)
            body.after_workout = afterWorkout
        api.request("POST", "stretch-sessions/start/", body, function(ok, status, data, error) {
            if (ok)
                return play(data)
            // One is running already: carry on with that one.
            if (status === 409 && data && data.id) {
                return api.request("GET", "stretch-sessions/" + data.id + "/", null, function(ok2, status2, running, error2) {
                    if (ok2)
                        play(running)
                    else
                        failed(status2, error2)
                })
            }
            failed(status, error)
        })
    }

    function failed(status, error) {
        saving = false
        if (status === 0 && offlineSteps.length > 0) {
            offline = true
            steps = offlineSteps
            ready = true
            lastTick = Date.now()
            startStep(0, false)
        } else {
            errorText = error
        }
    }

    function play(data) {
        saving = false
        session = data
        Store.stretchingChanged = true
        steps = Store.stretchSteps(Store.sessionItems(data), Store.stretches || {})
        ready = true
        lastTick = Date.now()
        startStep(0, false)
    }

    // A guided session's stretch done (with the seconds held) or skipped.
    function mark(performed, isDone) {
        if (!session || !performed)
            return
        api.request("POST", "stretch-sessions/" + session.id + "/mark/", {
            performed_stretch: performed, done: isDone,
            actual_seconds: isDone ? Math.round(heldMs / 1000) : null
        }, function(ok, status, data, error) {
            if (!ok)
                errorText = error
        })
    }

    // To step `at`; leaving a stretch marks it, skipped with `skipped`.
    function startStep(at, skipped) {
        var current = steps[index]
        var next = steps[at]
        if (current && ready && at > index && (!next || next.performed !== current.performed)) {
            mark(current.performed, !skipped)
            heldMs = 0
        }
        if (at >= steps.length) {
            if (!done)
                chime(doneSound)
            done = true
            index = steps.length
            return
        }
        index = at
        remainingMs = steps[at].seconds * 1000
        stepEndsAt = Date.now() + remainingMs
    }

    function tick() {
        var now = Date.now()
        if (ready && !paused && !done) {
            activeMs += now - lastTick
            if (step && step.kind === "hold")
                heldMs += now - lastTick
            remainingMs = Math.max(0, stepEndsAt - now)
            if (remainingMs <= 0) {
                var next = steps[index + 1]
                if (next)
                    chime(next.kind === "hold" ? holdSound : stepSound)
                startStep(index + 1, false)
            }
        }
        lastTick = now
    }

    function togglePause() {
        if (paused)
            stepEndsAt = Date.now() + remainingMs
        paused = !paused
    }

    function finish() {
        if (offline) {
            syncQueue.enqueue("POST", "stretch-sessions/", {
                routine: routine.id,
                date: Store.isoDate(new Date()),
                duration: Store.toDuration(Math.max(60, activeMs / 1000)),
                notes: ""
            })
            Store.stretchingChanged = true
            return pageStack.pop()
        }
        if (!session)
            return pageStack.pop()
        saving = true
        api.request("POST", "stretch-sessions/" + session.id + "/complete/", null, function(ok, status, data, error) {
            saving = false
            if (!ok) {
                errorText = error
                return
            }
            Store.stretchingChanged = true
            pageStack.pop()
        })
    }

    function abandon() {
        if (!session)
            return pageStack.pop()
        api.request("POST", "stretch-sessions/" + session.id + "/abandon/", null, function(ok, status, data, error) {
            if (!ok) {
                errorText = error
                return
            }
            Store.stretchingChanged = true
            pageStack.pop()
        })
    }

    Component.onCompleted: {
        Store.ensureStretches(api, function() { begin() })
    }

    SoundEffect {
        id: holdSound
        source: Qt.resolvedUrl("../sounds/hold.wav")
    }
    SoundEffect {
        id: stepSound
        source: Qt.resolvedUrl("../sounds/step.wav")
    }
    SoundEffect {
        id: doneSound
        source: Qt.resolvedUrl("../sounds/done.wav")
    }

    // Keeps counting with the screen off.
    KeepAlive {
        enabled: page.ready && !page.done && !page.paused
    }

    Timer {
        interval: 200
        repeat: true
        running: page.ready && !page.done
        onTriggered: page.tick()
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Abandon session")
                onClicked: remorse.execute(qsTr("Abandoning session"), function() { page.abandon() })
            }
            MenuItem {
                visible: page.ready && !page.done
                text: qsTr("Finish session")
                onClicked: page.finish()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: page.title
                description: Store.formatDuration(page.activeMs / 1000)
            }

            Label {
                visible: page.errorText !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.errorColor
                text: page.errorText
            }

            Column {
                visible: page.ready && !page.done && page.step !== null
                width: parent.width
                spacing: Theme.paddingMedium

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    text: page.step ? page.stepTitle(page.step.kind) : ""
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeExtraLarge
                    text: page.step ? Store.stretchName(page.step.stretch) : ""
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: Theme.fontSizeMedium
                    text: page.step ? [page.sideText(page.step.side),
                                       page.step.sets > 1 ? qsTr("set %1/%2").arg(page.step.set).arg(page.step.sets) : ""]
                                      .filter(function(p) { return p }).join(" · ") : ""
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: Theme.fontSizeHuge * 1.5
                    color: page.paused ? Theme.secondaryColor : Theme.primaryColor
                    text: Math.ceil(page.remainingMs / 1000)
                }
                Label {
                    readonly property var nextStretch: {
                        var at = Store.nextStretchStep(page.steps, page.index)
                        return at < page.steps.length ? page.steps[at].stretch : null
                    }
                    visible: nextStretch !== null
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryColor
                    text: visible ? qsTr("Next up:") + " " + Store.stretchName(nextStretch) : ""
                }

                ButtonLayout {
                    Button {
                        text: page.paused ? qsTr("Resume") : qsTr("Pause")
                        onClicked: page.togglePause()
                    }
                    Button {
                        text: qsTr("Next step")
                        onClicked: page.startStep(page.index + 1, false)
                    }
                    Button {
                        text: qsTr("Skip stretch")
                        onClicked: page.startStep(Store.nextStretchStep(page.steps, page.index), true)
                    }
                }
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: !page.ready && page.errorText === ""
            }

            Column {
                visible: page.done
                width: parent.width
                spacing: Theme.paddingLarge
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    text: qsTr("All stretches done - nice work.")
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    enabled: !page.saving
                    text: qsTr("Finish session")
                    onClicked: page.finish()
                }
            }
        }
    }
}
