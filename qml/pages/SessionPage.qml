import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// The full view of a session: every exercise with all its sets. The place
// for reviewing a workout and correcting mistakes (edit/delete); logging
// during a workout happens in TrainingPage. A finished workout offers a
// cool-down, like the web's workout page.
Page {
    id: page

    property alias sessionId: controller.sessionId
    property real elapsed: 0

    readonly property bool inProgress: controller.inProgress

    SessionController {
        id: controller
        onEnded: {
            if (status === "abandoned")
                pageStack.pop()
        }
    }

    function openLogDialog(pe) {
        var p = controller.prefill(pe)
        var dialog = pageStack.push(Qt.resolvedUrl("LogSetDialog.qml"), {
            exerciseName: Store.shown(pe, "exercise_name"),
            incrementKg: pe.weight_increment ? parseFloat(pe.weight_increment) : 2.5,
            initialWeightKg: p.weightKg,
            initialReps: p.reps,
            initialRpe: p.rpe,
            initialRir: p.rir,
            hint: hintFor(p)
        })
        dialog.accepted.connect(function() { controller.logSet(pe, dialogValues(dialog)) })
    }

    function openEditDialog(pe, set) {
        var dialog = pageStack.push(Qt.resolvedUrl("LogSetDialog.qml"), {
            exerciseName: Store.shown(pe, "exercise_name") + " - " + qsTr("set %1").arg(set.set_number),
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
        dialog.accepted.connect(function() { controller.updateSet(set, dialogValues(dialog)) })
    }

    function dialogValues(dialog) {
        return {
            weightKg: dialog.weightKg,
            reps: dialog.reps,
            rpe: dialog.rpe,
            rir: dialog.rir,
            isWarmup: dialog.isWarmup,
            isFailure: dialog.isFailure,
            notes: dialog.notes
        }
    }

    function hintFor(p) {
        if (p.source === "set")
            return qsTr("Prefilled from your previous set.")
        if (p.source === "previous")
            return qsTr("Prefilled from last time (%1).").arg(Format.formatDate(new Date(p.date), Formatter.DateMedium))
        if (p.source === "suggestion")
            return qsTr("Prefilled with the smart suggestion.")
        if (p.source === "target")
            return qsTr("Prefilled from the program target.")
        return ""
    }

    function addExercise() {
        var picker = pageStack.push(Qt.resolvedUrl("ExercisePickerPage.qml"), { picking: true })
        picker.selected.connect(function(exerciseId) { controller.addExercise(exerciseId) })
    }

    function openTraining() {
        pageStack.replace(Qt.resolvedUrl("TrainingPage.qml"), { sessionId: controller.sessionId })
    }

    Component.onCompleted: controller.load()

    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: page.inProgress && Qt.application.active
        onTriggered: page.elapsed = Store.elapsedSince(controller.session.started_at)
    }

    RemorsePopup {
        id: remorse
    }

    onStatusChanged: {
        if (status === PageStatus.Active && Store.stretchingChanged && list.headerItem)
            list.headerItem.reloadCooldown()
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: controller.exercises

        PullDownMenu {
            busy: controller.loading
            visible: page.inProgress
            MenuItem {
                text: qsTr("Finish workout")
                onClicked: remorse.execute(qsTr("Finishing workout"), function() { controller.end("completed") })
            }
            MenuItem {
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }
            MenuItem {
                text: qsTr("Training mode")
                onClicked: page.openTraining()
            }
        }

        PushUpMenu {
            visible: page.inProgress
            MenuItem {
                text: qsTr("Abandon workout")
                onClicked: remorse.execute(qsTr("Abandoning workout"), function() { controller.end("abandoned") })
            }
        }

        header: Column {
            width: parent.width
            function reloadCooldown() { cooldown.reload() }
            PageHeader {
                title: controller.title
                description: {
                    var session = controller.session
                    if (!session)
                        return ""
                    if (page.inProgress)
                        return Store.formatDuration(page.elapsed)
                    var status = controller.pendingEnd || session.status
                    return (status === "completed" ? qsTr("Completed") : qsTr("Abandoned"))
                           + " - " + Format.formatDate(new Date(session.started_at), Formatter.DateMedium)
                           + " " + Format.formatDate(new Date(session.started_at), Formatter.TimeValue)
                }
            }
            ErrorBanner {
                text: controller.errorText
                showRetry: true
                onRetry: controller.load()
            }
            SyncStatus {}
            RestTimer {}
            CooldownCard {
                id: cooldown
                session: controller.session
            }
        }

        delegate: Column {
            id: exerciseColumn
            property var pe: modelData
            width: list.width
            bottomPadding: Theme.paddingLarge

            SectionHeader {
                text: Store.shown(pe, "exercise_name")
                // Tapping the name shows the exercise's guide.
                MouseArea {
                    anchors.fill: parent
                    onClicked: pageStack.push(Qt.resolvedUrl("ExercisePage.qml"), { exerciseId: pe.exercise })
                }
            }

            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                horizontalAlignment: Text.AlignRight
                text: {
                    var target = Store.targetText(pe, settings.unitSystem)
                    if (!target)
                        return ""
                    return qsTr("Target") + ": " + target + " ("
                            + qsTr("%1/%2 done").arg(Store.workingSetCount(pe)).arg(pe.set_count) + ")"
                }
            }

            Label {
                property var before: controller.previous[pe.exercise]
                visible: page.inProgress && before !== undefined && before !== null
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.Wrap
                text: visible ? qsTr("Last time: %1").arg(Store.summarizeSets(before.sets, settings.unitSystem)) : ""
            }

            SuggestionLabel {
                visible: page.inProgress && headline !== "" && Store.workingSetCount(pe) === 0
                suggestion: controller.suggestions[pe.id] || null
                pe: modelData
                alignment: Text.AlignRight
            }

            Repeater {
                model: pe.sets
                delegate: SetItem {
                    id: setItem
                    width: list.width
                    set: modelData
                    // Queued sets have no server id yet to edit or delete.
                    menu: page.inProgress && !modelData.pending ? setMenu : null
                    onClicked: if (page.inProgress && !modelData.pending) page.openEditDialog(pe, modelData)

                    Component {
                        id: setMenu
                        ContextMenu {
                            MenuItem {
                                text: qsTr("Edit")
                                onClicked: page.openEditDialog(pe, setItem.set)
                            }
                            MenuItem {
                                text: qsTr("Delete")
                                onClicked: {
                                    // The menu (and names in its scope) is gone by
                                    // the time the remorse runs out.
                                    var set = setItem.set
                                    var target = controller
                                    setItem.remorseDelete(function() { target.deleteSet(set) })
                                }
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
            enabled: controller.session !== null && controller.exercises.length === 0
            text: qsTr("No exercises yet")
            hintText: page.inProgress ? qsTr("Pull down to add an exercise") : ""
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: controller.loading && controller.session === null
        }

        VerticalScrollDecorator {}
    }
}
