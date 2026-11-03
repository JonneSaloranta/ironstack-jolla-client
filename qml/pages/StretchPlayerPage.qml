import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.KeepAlive 1.2
import QtMultimedia 5.6
import "../js/store.js" as Store

// A routine as a guided session, like the web's player: get ready, hold
// each stretch (each side, each set), rest in between, with pause and
// skip. Played here on the phone - the API can only take a finished
// session as a quick log (IronStack #34) - and logged as done with the
// routine and the time spent when finished. Chimes like the web's timer
// (Settings: "Stretching timer sound"): a double one when a hold starts,
// a single one when any other step runs out, three at the end; skipping
// by hand is silent.
Page {
    id: page

    property var routine
    property var steps: []
    property int index: 0
    property bool paused: false
    property real stepEndsAt: 0
    property real remainingMs: 0
    property real activeMs: 0
    property real lastTick: 0
    property bool done: steps.length === 0
    property bool saving: false
    property string errorText: ""

    readonly property var step: steps[index] || null

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

    function startStep(at) {
        if (at >= steps.length) {
            if (!done)
                chime(doneSound)
            done = true
            return
        }
        index = at
        remainingMs = steps[at].seconds * 1000
        stepEndsAt = Date.now() + remainingMs
    }

    function tick() {
        var now = Date.now()
        if (!paused && !done) {
            activeMs += now - lastTick
            remainingMs = Math.max(0, stepEndsAt - now)
            if (remainingMs <= 0) {
                var next = steps[index + 1]
                if (next)
                    chime(next.kind === "hold" ? holdSound : stepSound)
                startStep(index + 1)
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
        saving = true
        api.request("POST", "stretch-sessions/", {
            routine: routine.id,
            date: Store.isoDate(new Date()),
            duration: Store.toDuration(Math.max(60, activeMs / 1000)),
            notes: ""
        }, function(ok, status, data, error) {
            saving = false
            if (!ok) {
                errorText = error
                return
            }
            Store.stretchingChanged = true
            pageStack.pop()
        })
    }

    Component.onCompleted: {
        lastTick = Date.now()
        startStep(0)
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
        enabled: !page.done && !page.paused
    }

    Timer {
        interval: 200
        repeat: true
        running: !page.done
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
                onClicked: remorse.execute(qsTr("Abandoning session"), function() { pageStack.pop() })
            }
            MenuItem {
                visible: !page.done
                text: qsTr("Finish session")
                onClicked: page.finish()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: Store.contentName(page.routine.name)
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
                visible: !page.done && page.step !== null
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
                        onClicked: page.startStep(page.index + 1)
                    }
                    Button {
                        text: qsTr("Skip stretch")
                        onClicked: page.startStep(Store.nextStretchStep(page.steps, page.index))
                    }
                }
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
