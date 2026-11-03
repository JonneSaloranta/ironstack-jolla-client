import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/texts.js" as Texts

// One program and its workouts. Your own programs can be edited like on the
// web - details, workouts added, edited, reordered and deleted; a template
// can be copied to your programs.
Page {
    id: page

    // Opened with a program from a list (shown right away) or just its id;
    // either way it's loaded fresh from the server.
    property var program: null
    property int programId: program ? program.id : -1
    property bool loading: false
    property string errorText: ""

    readonly property bool editable: program ? Store.programGroup(program) === "own" : false
    readonly property var workouts: program ? (program.workouts || []).slice().sort(function(a, b) {
        return a.order - b.order || a.id - b.id
    }) : []

    signal changed()

    function weekdayName(index) {
        // Django weekday: 0 = Monday. Qt.locale().dayName: 0 = Sunday.
        return Qt.locale().dayName((index + 1) % 7, Locale.ShortFormat)
    }

    function load(keepError) {
        loading = true
        api.request("GET", "programs/" + programId + "/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            errorText = keepError || ""
            program = data
        })
    }

    // A write, then a fresh copy; a refused write's error stays shown.
    function write(method, path, body) {
        api.request(method, path, body, function(ok, status, data, error) {
            changed()
            load(ok ? "" : error)
        })
    }


    function editProgram() {
        var dialog = pageStack.push(Qt.resolvedUrl("ProgramEditDialog.qml"), { program: program })
        dialog.accepted.connect(function() { write("PATCH", "programs/" + programId + "/", dialog.body()) })
    }

    function addWorkout() {
        var dialog = pageStack.push(Qt.resolvedUrl("WorkoutEditDialog.qml"))
        dialog.accepted.connect(function() {
            var body = dialog.body()
            body.program = programId
            var last = workouts.length ? workouts[workouts.length - 1].order : -1
            body.order = last + 1
            write("POST", "workouts/", body)
        })
    }

    function editWorkout(workout) {
        var dialog = pageStack.push(Qt.resolvedUrl("WorkoutEditDialog.qml"), { workout: workout })
        dialog.accepted.connect(function() { write("PATCH", "workouts/" + workout.id + "/", dialog.body()) })
    }

    // Swaps two workouts' order, the web's up/down arrows.
    function move(index, direction) {
        var other = Store.swapTarget(workouts.length, index, direction)
        if (other < 0)
            return
        var a = workouts[index]
        var b = workouts[other]
        var orderA = a.order === b.order ? other : b.order
        var orderB = a.order === b.order ? index : a.order
        api.request("PATCH", "workouts/" + a.id + "/", { order: orderA }, function(ok, status, data, error) {
            if (!ok)
                return load(error)
            write("PATCH", "workouts/" + b.id + "/", { order: orderB })
        })
    }

    function copy() {
        loading = true
        // The web's Copy: your own program with every workout and exercise.
        api.request("POST", "programs/" + programId + "/copy/", null, function(ok, status, data, error) {
            loading = false
            if (!ok) {
                errorText = error
                return
            }
            changed()
            Store.whenIdle(pageStack, function() { pageStack.replace(Qt.resolvedUrl("ProgramPage.qml"), { programId: data.id }) })
        })
    }

    function remove() {
        remorse.execute(qsTr("Deleting program"), function() {
            api.request("DELETE", "programs/" + programId + "/", null, function(ok, status, data, error) {
                if (!ok) {
                    errorText = error
                    return
                }
                changed()
                pageStack.pop()
            })
        })
    }

    Component.onCompleted: load()

    RemorsePopup {
        id: remorse
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.workouts

        PullDownMenu {
            busy: page.loading
            MenuItem {
                visible: page.editable
                text: qsTr("Delete program")
                onClicked: page.remove()
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Edit program")
                onClicked: page.editProgram()
            }
            MenuItem {
                visible: !page.editable && page.program !== null
                text: qsTr("Copy to my programs")
                onClicked: page.copy()
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Add workout")
                onClicked: page.addWorkout()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.program ? Store.contentName(page.program.name) : ""
                description: page.program && page.program.is_continuous ? qsTr("Continuous program") : ""
            }
            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }
            Label {
                visible: text.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: page.program ? Texts.contentText(page.program.description || "") : ""
            }
        }

        delegate: ListItem {
            id: item
            // Grows with the text size setting instead of clipping it.
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            onClicked: {
                var workoutPage = pageStack.push(Qt.resolvedUrl("WorkoutPage.qml"),
                                                 { workout: modelData, editable: page.editable })
                workoutPage.changed.connect(page.load)
            }
            menu: page.editable ? workoutMenu : null

            Component {
                id: workoutMenu
                ContextMenu {
                    MenuItem {
                        text: qsTr("Edit")
                        onClicked: page.editWorkout(modelData)
                    }
                    MenuItem {
                        visible: index > 0
                        text: qsTr("Move up")
                        onClicked: page.move(index, -1)
                    }
                    MenuItem {
                        visible: index < page.workouts.length - 1
                        text: qsTr("Move down")
                        onClicked: page.move(index, 1)
                    }
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: {
                            var id = modelData.id
                            item.remorseDelete(function() { page.write("DELETE", "workouts/" + id + "/", null) })
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
                    text: Store.contentName(modelData.name)
                }
                Label {
                    width: parent.width
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("%n exercise(s)", "", modelData.prescriptions.length)
                          + (Store.present(modelData.scheduled_weekday)
                             ? " - " + page.weekdayName(modelData.scheduled_weekday) : "")
                }
            }
        }

        ViewPlaceholder {
            enabled: page.program && !page.loading && page.workouts.length === 0
            text: qsTr("No workouts in this program")
            hintText: page.editable ? qsTr("Pull down to add a workout") : ""
        }

        VerticalScrollDecorator {}
    }
}
