import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Training mode: one exercise at a time, made for holding a phone between
// sets - the same idea as IronStack's web training mode (docs/UI.md
// "Training mode"). Opens on the first exercise with sets left and moves on
// by itself when that one is done; swiping (or the arrows) goes anywhere.
// Corrections live in the full view (SessionPage), not here.
Page {
    id: page

    // Built for one hand in portrait: the steppers and the log button sit
    // where a thumb reaches, which a 720 px tall landscape screen can't fit.
    allowedOrientations: Orientation.Portrait

    property alias sessionId: controller.sessionId
    property real elapsed: 0
    property bool positioned: false

    readonly property var exercises: controller.exercises
    readonly property bool allDone: exercises.length > 0 && Store.firstIncompleteIndex(exercises) < 0

    SessionController {
        id: controller
        onEnded: pageStack.pop()
    }

    // A stable model: the view only gets a new row when an exercise is
    // added, so logging or syncing a set never resets the view or its
    // position. Rows read their data from controller.exercises[index].
    ListModel {
        id: rows
    }

    onExercisesChanged: {
        while (rows.count < exercises.length)
            rows.append({})
        if (!positioned && controller.session !== null && exercises.length > 0) {
            positioned = true
            var first = Store.firstIncompleteIndex(exercises)
            view.positionViewAtIndex(first < 0 ? exercises.length - 1 : first, ListView.Beginning)
            view.currentIndex = first < 0 ? exercises.length - 1 : first
        }
    }

    function goTo(index) {
        if (index >= 0 && index < rows.count)
            view.currentIndex = index
    }

    function logged(index) {
        // Moves on once this exercise has all its sets - after a moment, so
        // the logged set is seen landing first.
        if (Store.isExerciseComplete(exercises[index])) {
            var next = Store.firstIncompleteIndex(exercises)
            if (next >= 0) {
                advance.target = next
                advance.restart()
            }
        }
    }

    Timer {
        id: advance
        property int target: 0
        interval: 700
        onTriggered: page.goTo(target)
    }

    function addExercise() {
        var picker = pageStack.push(Qt.resolvedUrl("ExercisePickerPage.qml"))
        picker.selected.connect(function(exerciseId) {
            var before = rows.count
            controller.addExercise(exerciseId)
            jumpToNew.from = before
        })
    }

    // After adding an exercise, show it as soon as it arrives.
    Connections {
        id: jumpToNew
        property int from: -1
        target: page
        onExercisesChanged: {
            if (jumpToNew.from >= 0 && page.exercises.length > jumpToNew.from) {
                page.goTo(page.exercises.length - 1)
                jumpToNew.from = -1
            }
        }
    }

    Component.onCompleted: controller.load()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: controller.inProgress && Qt.application.active
        onTriggered: page.elapsed = Store.elapsedSince(controller.session.started_at)
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: height

        PullDownMenu {
            busy: controller.loading || syncQueue.syncing
            MenuItem {
                text: qsTr("Abandon workout")
                onClicked: remorse.execute(qsTr("Abandoning workout"), function() { controller.end("abandoned") })
            }
            MenuItem {
                text: qsTr("Finish workout")
                onClicked: remorse.execute(qsTr("Finishing workout"), function() { controller.end("completed") })
            }
            MenuItem {
                text: qsTr("Full view")
                onClicked: pageStack.replace(Qt.resolvedUrl("SessionPage.qml"), { sessionId: page.sessionId })
            }
            MenuItem {
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }
        }

        Column {
            id: top
            width: parent.width

            PageHeader {
                title: controller.title
                description: Store.formatDuration(page.elapsed)
            }

            ErrorBanner {
                text: controller.errorText
                showRetry: true
                onRetry: controller.load()
            }

            Label {
                visible: controller.offline && syncQueue.count === 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingSmall
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("No connection. Sets are saved on this phone and sent later.")
            }

            SyncStatus {}

            // One dot per exercise: filled when done, highlighted for the
            // one shown.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium
                height: Theme.paddingLarge
                Repeater {
                    model: rows.count
                    // Shown: bigger. Done: filled. To do: an outline.
                    delegate: Rectangle {
                        property bool done: page.exercises[index] !== undefined
                                            && Store.isExerciseComplete(page.exercises[index])
                        property bool current: index === view.currentIndex
                        anchors.verticalCenter: parent.verticalCenter
                        width: current ? Theme.paddingLarge : Theme.paddingMedium
                        height: width
                        radius: width / 2
                        color: done ? Theme.highlightColor : "transparent"
                        border.width: Math.max(1, Math.round(Theme.pixelRatio * 1.5))
                        border.color: current || done ? Theme.highlightColor : Theme.secondaryColor
                    }
                }
            }
        }

        SilicaListView {
            id: view
            anchors.top: top.bottom
            anchors.bottom: restTimer.top
            width: parent.width
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 300
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            cacheBuffer: width * 2
            model: rows

            delegate: ExercisePanel {
                width: view.width
                height: view.height
                pe: page.exercises[index] || null
                index_: index
                count: rows.count
                previous: pe ? (controller.previous[pe.exercise] || null) : null
                prefillValues: pe ? controller.prefill(pe) : null
                inProgress: controller.inProgress
                allDone: page.allDone
                onLogSet: {
                    controller.logSet(pe, values)
                    page.logged(index)
                }
                onPrevious_: page.goTo(index - 1)
                onNext_: page.goTo(index + 1)
                onFinish: remorse.execute(qsTr("Finishing workout"), function() { controller.end("completed") })
            }

            ViewPlaceholder {
                enabled: controller.session !== null && rows.count === 0
                text: qsTr("No exercises yet")
                hintText: qsTr("Pull down to add an exercise")
            }

            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Large
                running: controller.loading && controller.session === null
            }
        }

        RestTimer {
            id: restTimer
            anchors.bottom: parent.bottom
        }
    }
}
