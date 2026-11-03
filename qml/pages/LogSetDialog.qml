import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/store.js" as Store

// Log a new set or edit an existing one. Every field is just a default -
// the user always has the final say on weight and reps.
Dialog {
    id: dialog

    property string exerciseName
    property bool editing: false
    // Prefill, in kilograms (the API's unit).
    property var initialWeightKg
    property var initialReps
    property var initialRpe: null
    property var initialRir: null
    property bool initialWarmup: false
    property bool initialFailure: false
    property string initialNotes: ""
    property real incrementKg: 2.5
    property string hint: ""

    // Results, valid after acceptance.
    property real weightKg
    property int reps
    property var rpe: null
    property var rir: null
    property bool isWarmup
    property bool isFailure
    property string notes

    readonly property string unitSystem: settings.unitSystem
    readonly property real incrementDisplay: Store.isImperial(unitSystem) ? 5 : incrementKg

    canAccept: weightField.acceptableInput && repsField.acceptableInput
               && (rpeField.text === "" || rpeField.acceptableInput)
               && (rirField.text === "" || rirField.acceptableInput)

    function stepWeight(direction) {
        var current = parseFloat(weightField.text.replace(",", ".")) || 0
        var next = Math.max(0, current + direction * incrementDisplay)
        weightField.text = Store.formatNumber(next)
    }

    onAccepted: {
        weightKg = Store.displayToKg(weightField.text, unitSystem)
        reps = parseInt(repsField.text, 10)
        rpe = rpeField.text === "" ? null : parseFloat(rpeField.text.replace(",", "."))
        rir = rirField.text === "" ? null : parseInt(rirField.text, 10)
        isWarmup = warmupSwitch.checked
        isFailure = failureSwitch.checked
        notes = notesField.text
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: dialog.editing ? qsTr("Save") : qsTr("Log set")
                title: dialog.exerciseName
            }

            Label {
                visible: dialog.hint.length > 0
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: dialog.hint
            }

            Row {
                width: parent.width
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-remove"
                    onClicked: dialog.stepWeight(-1)
                }
                TextField {
                    id: weightField
                    width: parent.width - 2 * Theme.itemSizeSmall
                    label: qsTr("Weight (%1)").arg(Store.weightUnit(dialog.unitSystem))
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^\d{1,4}([.,]\d{0,2})?$/ }
                    text: dialog.initialWeightKg !== undefined && dialog.initialWeightKg !== null
                          ? Store.formatNumber(Store.kgToDisplay(dialog.initialWeightKg, dialog.unitSystem))
                          : ""
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: repsField.focus = true
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-add"
                    onClicked: dialog.stepWeight(1)
                }
            }

            Row {
                width: parent.width
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-remove"
                    onClicked: repsField.text = String(Math.max(0, (parseInt(repsField.text, 10) || 0) - 1))
                }
                TextField {
                    id: repsField
                    width: parent.width - 2 * Theme.itemSizeSmall
                    label: qsTr("Reps")
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 999 }
                    text: dialog.initialReps !== undefined && dialog.initialReps !== null
                          ? String(dialog.initialReps) : ""
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: if (dialog.canAccept) dialog.accept()
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-add"
                    onClicked: repsField.text = String((parseInt(repsField.text, 10) || 0) + 1)
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                TextField {
                    id: rpeField
                    width: parent.width / 2
                    label: qsTr("RPE (optional)")
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^\d{1,2}([.,]\d)?$/ }
                    text: dialog.initialRpe !== null && dialog.initialRpe !== undefined
                          ? Store.formatNumber(parseFloat(dialog.initialRpe)) : ""
                }
                TextField {
                    id: rirField
                    width: parent.width / 2
                    label: qsTr("RIR (optional)")
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 20 }
                    text: dialog.initialRir !== null && dialog.initialRir !== undefined
                          ? String(dialog.initialRir) : ""
                }
            }

            TextSwitch {
                id: warmupSwitch
                text: qsTr("Warm-up set")
                description: qsTr("Not counted for records, progression or analytics")
                checked: dialog.initialWarmup
            }

            TextSwitch {
                id: failureSwitch
                text: qsTr("Taken to failure")
                checked: dialog.initialFailure
            }

            TextArea {
                id: notesField
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.initialNotes
            }
        }
    }
}
