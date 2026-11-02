import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store
import "../js/texts.js" as Texts

// One exercise, like the web's exercise page and guide: what it works,
// how to do it (instructions and images, translated like the web), and
// your records for it. Your own exercises can be edited or deactivated.
Page {
    id: page

    property int exerciseId
    property var exercise: null
    property var records: []
    property bool loading: true
    property string errorText: ""

    readonly property bool editable: exercise !== null && exercise.is_custom

    // Built-in instructions are translated by the web's catalog too.
    function text(value) {
        return Texts.contentText(value)
    }

    function movementText(value) {
        if (value === "compound")
            return qsTr("Compound")
        if (value === "isolation")
            return qsTr("Isolation")
        return value || ""
    }

    function weightModeText(value) {
        if (value === "per_hand")
            return qsTr("Per hand / dumbbell")
        return qsTr("Total load")
    }

    function load() {
        loading = true
        errorText = ""
        Store.ensureLookups(api, function() {
            api.request("GET", "exercises/" + exerciseId + "/", null, function(ok, status, data, error) {
                loading = false
                if (!ok) {
                    errorText = error
                    return
                }
                exercise = data
            })
        })
        var found = []
        Store.fetchAll(api, "records/?page_size=100", function(results) {
            found = found.concat(results.filter(function(r) { return r.exercise === exerciseId }))
        }, function(ok) {
            if (ok)
                records = found
        })
    }

    function deactivate() {
        api.request("DELETE", "exercises/" + exerciseId + "/", null, function(ok, status, data, error) {
            if (!ok) {
                errorText = error
                return
            }
            Store.exercisesChanged = true
            pageStack.pop()
        })
    }

    Component.onCompleted: load()
    onStatusChanged: {
        if (status === PageStatus.Active && exercise !== null && Store.exercisesChanged)
            load()
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.editable || page.exercise !== null
            busy: page.loading
            MenuItem {
                visible: page.editable
                text: qsTr("Deactivate")
                onClicked: remorse.execute(qsTr("Deactivating exercise"), page.deactivate)
            }
            MenuItem {
                visible: page.editable
                text: qsTr("Edit")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("ExerciseEditDialog.qml"), { exercise: page.exercise })
                    dialog.accepted.connect(function() {
                        api.request("PATCH", "exercises/" + page.exerciseId + "/", dialog.body(),
                                    function(ok, status, data, error) {
                            if (!ok) {
                                page.errorText = error
                                return
                            }
                            Store.exercisesChanged = true
                            page.exercise = data
                        })
                    })
                }
            }
            MenuItem {
                visible: page.exercise !== null
                text: qsTr("Strength trend")
                onClicked: pageStack.push(Qt.resolvedUrl("ExerciseProgressPage.qml"), { exercise: page.exercise })
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingSmall

            PageHeader {
                title: page.exercise ? Store.contentName(page.exercise.name) : ""
                description: page.exercise && page.exercise.is_custom ? qsTr("Custom") : ""
            }

            ErrorBanner {
                text: page.errorText
                showRetry: true
                onRetry: page.load()
            }

            DetailItem {
                visible: page.exercise !== null
                label: qsTr("Movement type")
                value: page.exercise ? page.movementText(page.exercise.movement_type) : ""
            }
            DetailItem {
                visible: page.exercise !== null
                label: qsTr("Weight logging")
                value: page.exercise ? page.weightModeText(page.exercise.weight_input_mode) : ""
            }
            DetailItem {
                visible: page.exercise !== null && Store.present(page.exercise.equipment)
                label: qsTr("Equipment")
                value: page.exercise && Store.present(page.exercise.equipment) ? Store.equipmentName(page.exercise.equipment) : ""
            }
            DetailItem {
                visible: page.exercise !== null && page.exercise.primary_muscle_groups.length > 0
                label: qsTr("Primary muscles")
                value: page.exercise ? page.exercise.primary_muscle_groups.map(Store.muscleGroupName).join(", ") : ""
            }
            DetailItem {
                visible: page.exercise !== null && page.exercise.secondary_muscle_groups.length > 0
                label: qsTr("Secondary muscles")
                value: page.exercise ? page.exercise.secondary_muscle_groups.map(Store.muscleGroupName).join(", ") : ""
            }

            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: page.exercise ? page.text(page.exercise.description) : ""
            }

            SectionHeader {
                visible: instructions.text !== "" || images.count > 0
                text: qsTr("Instructions")
            }

            Repeater {
                id: images
                model: page.exercise ? page.exercise.images : []
                delegate: Column {
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    spacing: Theme.paddingSmall
                    Image {
                        width: parent.width
                        fillMode: Image.PreserveAspectFit
                        source: modelData.image
                        asynchronous: true
                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }
                    }
                    Label {
                        visible: text !== ""
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: [modelData.caption, modelData.attribution].filter(function(part) { return part }).join(" - ")
                    }
                }
            }

            Label {
                id: instructions
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                text: page.exercise ? page.text(page.exercise.instructions) : ""
            }
            Label {
                visible: text !== ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                text: page.exercise ? page.exercise.instructions_attribution || "" : ""
            }

            SectionHeader {
                visible: page.records.length > 0
                text: qsTr("Personal records")
            }
            Repeater {
                model: page.records
                delegate: RecordItem {
                    record: modelData
                }
            }
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading && page.exercise === null
    }
}
