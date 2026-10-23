import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    property int sessionId
    property var session: null
    property string title: ""
    property bool loading: false
    property string errorText: ""
    property real elapsed: 0

    readonly property bool inProgress: session !== null && session.is_in_progress

    function load() {
        loading = true
        api.request("GET", "sessions/" + sessionId + "/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                page.errorText = error
                return
            }
            page.errorText = ""
            page.session = data
            if (data.workout) {
                api.request("GET", "workouts/" + data.workout + "/", null, function(ok2, status2, workout) {
                    page.title = ok2 ? workout.name : qsTr("Workout")
                    syncCover()
                })
            } else {
                page.title = qsTr("Freeform workout")
                syncCover()
            }
        })
    }

    function syncCover() {
        if (!session)
            return
        if (session.is_in_progress) {
            settings.activeSessionId = session.id
            settings.activeSessionName = title
            settings.activeSessionStarted = session.started_at
        } else if (settings.activeSessionId === session.id) {
            settings.clearActiveSession()
        }
    }

    function targetText(pe) {
        if (!pe.set_count)
            return ""
        var reps = pe.min_reps && pe.max_reps && pe.min_reps !== pe.max_reps
                ? pe.min_reps + "-" + pe.max_reps : (pe.max_reps || pe.min_reps || "?")
        var text = qsTr("Target") + ": " + pe.set_count + " x " + reps
        if (pe.target_weight)
            text += " @ " + Store.formatWeight(pe.target_weight, settings.unitSystem)
        return text
    }

    function workingSetCount(pe) {
        return pe.sets.filter(function(s) { return !s.is_warmup }).length
    }

    // Prefill: the last set logged for this exercise in this session,
    // otherwise the plan's target. Never logged without the user
    // confirming the dialog.
    function openLogDialog(pe) {
        var last = pe.sets.length > 0 ? pe.sets[pe.sets.length - 1] : null
        var props = {
            exerciseName: pe.exercise_name,
            incrementKg: pe.weight_increment ? parseFloat(pe.weight_increment) : 2.5,
            initialWeightKg: last ? last.weight : pe.target_weight,
            initialReps: last ? last.reps : (pe.max_reps || pe.min_reps || null),
            initialRpe: last ? last.rpe : null,
            initialRir: last ? last.rir : null,
            hint: last ? qsTr("Prefilled from your previous set.")
                       : (pe.target_weight ? qsTr("Prefilled from the program target.") : "")
        }
        var dialog = pageStack.push(Qt.resolvedUrl("LogSetDialog.qml"), props)
        dialog.accepted.connect(function() {
            api.request("POST", "sets/", setPayload(dialog, { performed_exercise: pe.id,
                                                              target_reps: pe.max_reps || null }),
                        handleWrite)
        })
    }

    function openEditDialog(pe, set) {
        var dialog = pageStack.push(Qt.resolvedUrl("LogSetDialog.qml"), {
            exerciseName: pe.exercise_name + " - " + qsTr("set %1").arg(set.set_number),
            editing: true,
            incrementKg: pe.weight_increment ? parseFloat(pe.weight_increment) : 2.5,
            initialWeightKg: set.weight,
            initialReps: set.reps,
            initialRpe: set.rpe,
            initialRir: set.rir,
            initialWarmup: set.is_warmup,
            initialFailure: set.is_failure,
            initialNotes: set.notes || ""
        })
        dialog.accepted.connect(function() {
            api.request("PATCH", "sets/" + set.id + "/", setPayload(dialog, {}), handleWrite)
        })
    }

    function setPayload(dialog, extra) {
        extra.weight = dialog.weightKg
        extra.reps = dialog.reps
        extra.rpe = dialog.rpe
        extra.rir = dialog.rir
        extra.is_warmup = dialog.isWarmup
        extra.is_failure = dialog.isFailure
        extra.notes = dialog.notes
        return extra
    }

    function handleWrite(ok, status, data, error) {
        if (!ok)
            page.errorText = error
        load()
    }

    function deleteSet(set) {
        api.request("DELETE", "sets/" + set.id + "/", null, handleWrite)
    }

    function addExercise() {
        var picker = pageStack.push(Qt.resolvedUrl("ExercisePickerPage.qml"))
        picker.selected.connect(function(exerciseId) {
            api.request("POST", "performed-exercises/", { session: sessionId, exercise: exerciseId },
                        handleWrite)
        })
    }

    function end(newStatus) {
        api.request("PATCH", "sessions/" + sessionId + "/", { status: newStatus },
                    function(ok, status, data, error) {
            if (!ok) {
                page.errorText = error
                return
            }
            settings.clearActiveSession()
            page.session = data
            if (newStatus === "abandoned")
                pageStack.pop()
        })
    }

    Component.onCompleted: load()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: page.inProgress && Qt.application.active
        onTriggered: page.elapsed = Store.elapsedSince(page.session.started_at)
    }

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.session ? page.session.performed_exercises : []

        PullDownMenu {
            busy: page.loading
            visible: page.inProgress
            MenuItem {
                text: qsTr("Finish workout")
                onClicked: remorse.execute(qsTr("Finishing workout"), function() { page.end("completed") })
            }
            MenuItem {
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.load()
            }
        }

        PushUpMenu {
            visible: page.inProgress
            MenuItem {
                text: qsTr("Abandon workout")
                onClicked: remorse.execute(qsTr("Abandoning workout"), function() { page.end("abandoned") })
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.title
                description: !page.session ? ""
                             : page.inProgress ? Store.formatDuration(page.elapsed)
                             : (page.session.status === "completed" ? qsTr("Completed") : qsTr("Abandoned"))
                               + " - " + Store.formatDateTime(page.session.started_at)
            }
            ErrorBanner {
                text: page.errorText
            }
        }

        delegate: Column {
            id: exerciseColumn
            property var pe: modelData
            width: list.width
            bottomPadding: Theme.paddingLarge

            SectionHeader {
                text: pe.exercise_name
            }

            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                horizontalAlignment: Text.AlignRight
                text: {
                    var target = page.targetText(pe)
                    if (!target)
                        return ""
                    return target + " (" + qsTr("%1/%2 done").arg(page.workingSetCount(pe)).arg(pe.set_count) + ")"
                }
            }

            Repeater {
                model: pe.sets
                delegate: ListItem {
                    id: setItem
                    width: list.width
                    contentHeight: Theme.itemSizeSmall
                    menu: page.inProgress ? setMenu : null
                    onClicked: if (page.inProgress) page.openEditDialog(pe, modelData)

                    function remove() {
                        var set = modelData
                        remorseDelete(function() { page.deleteSet(set) })
                    }

                    Label {
                        id: numberLabel
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.horizontalPageMargin
                        width: Theme.itemSizeExtraSmall
                        color: Theme.secondaryColor
                        text: modelData.is_warmup ? "W" : modelData.set_number
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: numberLabel.right
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        truncationMode: TruncationMode.Fade
                        color: modelData.is_warmup ? Theme.secondaryColor : Theme.primaryColor
                        text: Store.formatWeight(modelData.weight, settings.unitSystem) + " x " + modelData.reps
                              + (modelData.rpe ? "  RPE " + parseFloat(modelData.rpe) : "")
                              + (modelData.rir !== null && modelData.rir !== undefined ? "  RIR " + modelData.rir : "")
                              + (modelData.is_failure ? "  " + qsTr("failure") : "")
                    }

                    Component {
                        id: setMenu
                        ContextMenu {
                            MenuItem {
                                text: qsTr("Edit")
                                onClicked: page.openEditDialog(pe, modelData)
                            }
                            MenuItem {
                                text: qsTr("Delete")
                                onClicked: setItem.remove()
                            }
                        }
                    }
                }
            }

            Button {
                visible: page.inProgress
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Log set")
                onClicked: page.openLogDialog(pe)
            }
        }

        footer: Item {
            width: list.width
            height: page.inProgress ? addButton.height + 2 * Theme.paddingLarge : 0
            Button {
                id: addButton
                visible: page.inProgress
                anchors.centerIn: parent
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }
        }

        ViewPlaceholder {
            enabled: page.session !== null && page.session.performed_exercises.length === 0
            text: qsTr("No exercises yet")
            hintText: page.inProgress ? qsTr("Pull down to add an exercise") : ""
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && page.session === null
        }

        VerticalScrollDecorator {}
    }
}
