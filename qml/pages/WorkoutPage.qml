import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// One workout of a program: its exercises and targets, and starting it.
// In your own programs (`editable`) exercises can be added, edited,
// reordered and removed, like on the web.
Page {
    id: page

    property var workout
    property bool editable: false
    property bool starting: false
    property bool loading: false
    property string errorText: ""

    readonly property var prescriptions: workout ? (workout.prescriptions || []).slice().sort(function(a, b) {
        return a.order - b.order || a.id - b.id
    }) : []

    signal changed()

    function prescriptionText(p) {
        var reps = p.min_reps && p.max_reps && p.min_reps !== p.max_reps
                ? p.min_reps + "-" + p.max_reps
                : (p.max_reps || p.min_reps || "?")
        var text = p.set_count + " x " + reps
        if (p.target_weight)
            text += " @ " + Store.formatWeight(p.target_weight, settings.unitSystem)
        if (p.target_rpe)
            text += " - RPE " + parseFloat(p.target_rpe)
        if (Store.present(p.target_rir))
            text += " - RIR " + p.target_rir
        return text
    }

    function load(keepError) {
        loading = true
        api.request("GET", "workouts/" + workout.id + "/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            errorText = keepError || ""
            workout = data
        })
    }

    // A write, then a fresh copy; a refused write's error stays shown.
    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            changed()
            load(ok ? "" : error)
        })
    }


    function addExercise() {
        var picker = pageStack.push(Qt.resolvedUrl("ExercisePickerPage.qml"), { picking: true, popOnSelect: false })
        picker.selected.connect(function(exerciseId) {
            // The picker makes way for the targets.
            var dialog = pageStack.replace(Qt.resolvedUrl("PrescriptionDialog.qml"), {
                exerciseId: exerciseId,
                exerciseName: picker.nameOf(exerciseId)
            })
            dialog.accepted.connect(function() {
                var body = dialog.body()
                body.workout = workout.id
                var last = prescriptions.length ? prescriptions[prescriptions.length - 1].order : -1
                body.order = last + 1
                write("POST", "prescriptions/", body)
            })
        })
    }

    function edit(prescription) {
        var dialog = pageStack.push(Qt.resolvedUrl("PrescriptionDialog.qml"), { prescription: prescription })
        dialog.accepted.connect(function() {
            var body = dialog.body()
            body.order = prescription.order
            write("PATCH", "prescriptions/" + prescription.id + "/", body)
        })
    }

    function editWorkout() {
        var dialog = pageStack.push(Qt.resolvedUrl("WorkoutEditDialog.qml"), { workout: workout })
        dialog.accepted.connect(function() { write("PATCH", "workouts/" + workout.id + "/", dialog.body()) })
    }

    function move(index, direction) {
        var other = Store.swapTarget(prescriptions.length, index, direction)
        if (other < 0)
            return
        var a = prescriptions[index]
        var b = prescriptions[other]
        var orderA = a.order === b.order ? other : b.order
        var orderB = a.order === b.order ? index : a.order
        api.request("PATCH", "prescriptions/" + a.id + "/", { order: orderA }, function(ok, status, data, error) {
            if (!ok)
                return load(error)
            write("PATCH", "prescriptions/" + b.id + "/", { order: orderB })
        })
    }

    function start() {
        if (settings.activeSessionId >= 0) {
            errorText = qsTr("Finish or abandon the workout in progress first.")
            return
        }
        starting = true
        errorText = ""
        api.request("POST", "sessions/", { workout: workout.id }, function(ok, status, data, error) {
            starting = false
            if (!ok) {
                page.errorText = error
                return
            }
            pageStack.replaceAbove(pageStack.find(function(p) { return p.objectName === "dashboard" }) || null,
                                   Qt.resolvedUrl("TrainingPage.qml"), { sessionId: data.id })
        })
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.prescriptions

        PullDownMenu {
            busy: page.starting || page.loading
            MenuItem {
                visible: page.editable
                text: qsTr("Edit workout")
                onClicked: page.editWorkout()
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Add exercise")
                onClicked: page.addExercise()
            }
            MenuItem {
                text: qsTr("Start workout")
                enabled: !page.starting
                onClicked: page.start()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.workout ? Store.contentName(page.workout.name) : ""
            }
            ErrorBanner {
                text: page.errorText
            }
            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.workout ? (page.workout.notes || "") : ""
            }
        }

        delegate: ListItem {
            id: item
            // Grows with the text size setting instead of clipping it.
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: pageStack.push(Qt.resolvedUrl("ExercisePage.qml"), { exerciseId: modelData.exercise })
            menu: page.editable ? prescriptionMenu : null

            Component {
                id: prescriptionMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Edit")
                        onClicked: page.edit(modelData)
                    }
                    MenuItem {
                        visible: index > 0
                        text: qsTr("Move up")
                        onClicked: page.move(index, -1)
                    }
                    MenuItem {
                        visible: index < page.prescriptions.length - 1
                        text: qsTr("Move down")
                        onClicked: page.move(index, 1)
                    }
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: {
                            var id = modelData.id
                            item.remorseDelete(function() { page.write("DELETE", "prescriptions/" + id + "/", null) })
                        }
                    }
                }
            }

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Store.contentName(modelData.exercise_name)
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: page.prescriptionText(modelData)
                          + (modelData.notes ? " - " + modelData.notes : "")
                }
            }
        }

        footer: Item {
            width: parent.width
            height: startButton.height + 2 * Theme.paddingLarge
            Button {
                id: startButton
                anchors.centerIn: parent
                text: qsTr("Start workout")
                enabled: !page.starting
                onClicked: page.start()
            }
        }

        ViewPlaceholder {
            enabled: page.workout && !page.loading && page.prescriptions.length === 0
            text: qsTr("No exercises yet")
            hintText: page.editable ? qsTr("Pull down to add an exercise") : ""
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.starting
        }

        VerticalScrollDecorator {}
    }
}
