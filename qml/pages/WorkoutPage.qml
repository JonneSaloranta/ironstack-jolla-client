import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

Page {
    id: page

    property var workout
    property bool namesLoaded: false
    property bool starting: false
    property string errorText: ""

    function prescriptionText(p) {
        var reps = p.min_reps && p.max_reps && p.min_reps !== p.max_reps
                ? p.min_reps + "-" + p.max_reps
                : (p.max_reps || p.min_reps || "?")
        var text = p.set_count + " x " + reps
        if (p.target_weight)
            text += " @ " + Store.formatWeight(p.target_weight, settings.unitSystem)
        if (p.target_rpe)
            text += " - RPE " + parseFloat(p.target_rpe)
        if (p.target_rir !== null && p.target_rir !== undefined)
            text += " - RIR " + p.target_rir
        return text
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

    Component.onCompleted: {
        Store.ensureExercises(api, workout.prescriptions.map(function(p) { return p.exercise }), function() {
            page.namesLoaded = true
        })
    }

    SilicaListView {
        anchors.fill: parent
        model: page.namesLoaded ? page.workout.prescriptions : []

        PullDownMenu {
            busy: page.starting
            MenuItem {
                text: qsTr("Start workout")
                enabled: !page.starting
                onClicked: page.start()
            }
        }

        header: Column {
            width: parent.width
            PageHeader {
                title: page.workout ? page.workout.name : ""
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
            // Grows with the text size setting instead of clipping it.
            contentHeight: Math.max(Theme.itemSizeMedium, textColumn.height + 2 * Theme.paddingMedium)
            enabled: false

            Column {
                id: textColumn
                anchors.verticalCenter: parent.verticalCenter
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    text: Store.exerciseName(modelData.exercise)
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: page.prescriptionText(modelData)
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

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: !page.namesLoaded || page.starting
        }

        VerticalScrollDecorator {}
    }
}
