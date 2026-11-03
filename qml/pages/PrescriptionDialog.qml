import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// An exercise in a workout: sets, rep range, targets and progression - the
// web's prescription form. Weights are entered in the user's unit and sent
// as kg, like the web form does. The page that opened it saves body().
Dialog {
    id: dialog

    property var prescription: null
    property int exerciseId: prescription ? prescription.exercise : 0
    property string exerciseName: prescription ? prescription.exercise_name : ""

    readonly property string unitSystem: settings.unitSystem
    readonly property var methods: ["double_progression", "linear", "percentage_based", "rpe_rir"]
    property int methodIndex: prescription ? Math.max(0, methods.indexOf(prescription.progression_method)) : 0

    function number(field) {
        var value = Store.parseNumber(field.text)
        return isNaN(value) ? null : value
    }
    function integer(field) {
        var value = parseInt(field.text, 10)
        return isNaN(value) ? null : value
    }
    function weight(field) {
        var kg = Store.displayToKg(field.text, unitSystem)
        return isNaN(kg) ? null : kg
    }
    function shown(kg) {
        return Store.present(kg) ? Store.formatNumber(Store.kgToDisplay(kg, unitSystem)) : ""
    }
    function text(value) {
        return Store.present(value) ? String(parseFloat(value)) : ""
    }

    function body() {
        return {
            exercise: exerciseId,
            set_count: integer(setsField),
            min_reps: integer(minRepsField),
            max_reps: integer(maxRepsField),
            target_weight: weight(weightField),
            target_rpe: number(rpeField),
            target_rir: integer(rirField),
            progression_method: methods[methodIndex],
            weight_increment: weight(incrementField),
            percentage_target: methods[methodIndex] === "percentage_based" ? number(percentageField) : null,
            notes: notesArea.text
        }
    }

    readonly property bool repsValid: !(integer(minRepsField) && integer(maxRepsField))
                                      || integer(minRepsField) <= integer(maxRepsField)
    canAccept: integer(setsField) > 0 && integer(minRepsField) > 0 && integer(maxRepsField) > 0 && repsValid

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: Store.contentName(dialog.exerciseName)
            }

            TextField {
                id: setsField
                width: parent.width
                label: qsTr("Sets")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 99 }
                text: dialog.prescription ? dialog.text(dialog.prescription.set_count) : "3"
            }
            Row {
                width: parent.width
                TextField {
                    id: minRepsField
                    width: parent.width / 2
                    label: qsTr("Min reps")
                    placeholderText: label
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 999 }
                    // The web form's defaults: 3 x 8-12.
                    text: dialog.prescription ? dialog.text(dialog.prescription.min_reps) : "8"
                }
                TextField {
                    id: maxRepsField
                    width: parent.width / 2
                    label: qsTr("Max reps")
                    placeholderText: label
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 999 }
                    text: dialog.prescription ? dialog.text(dialog.prescription.max_reps) : "12"
                }
            }
            Label {
                visible: !dialog.repsValid
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.errorColor
                text: qsTr("Minimum reps cannot exceed maximum reps.")
            }
            TextField {
                id: weightField
                width: parent.width
                label: qsTr("Target weight (%1)").arg(Store.weightUnit(dialog.unitSystem))
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^(\d{1,4}([.,]\d{0,2})?)?$/ }
                text: dialog.prescription ? dialog.shown(dialog.prescription.target_weight) : ""
            }
            Row {
                width: parent.width
                TextField {
                    id: rpeField
                    width: parent.width / 2
                    label: qsTr("Target RPE")
                    placeholderText: label
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    validator: RegExpValidator { regExp: /^(\d{1,2}([.,]\d)?)?$/ }
                    text: dialog.prescription ? dialog.text(dialog.prescription.target_rpe) : ""
                }
                TextField {
                    id: rirField
                    width: parent.width / 2
                    label: qsTr("Target RIR")
                    placeholderText: label
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 0; top: 20 }
                    text: dialog.prescription ? dialog.text(dialog.prescription.target_rir) : ""
                }
            }
            ComboBox {
                label: qsTr("Progression method")
                currentIndex: dialog.methodIndex
                menu: ContextMenu {
                    MenuItem { text: qsTr("Double progression"); onClicked: dialog.methodIndex = 0 }
                    MenuItem { text: qsTr("Linear"); onClicked: dialog.methodIndex = 1 }
                    MenuItem { text: qsTr("Percentage based"); onClicked: dialog.methodIndex = 2 }
                    MenuItem { text: qsTr("RPE/RIR based"); onClicked: dialog.methodIndex = 3 }
                }
            }
            TextField {
                id: incrementField
                width: parent.width
                label: qsTr("Weight increment (%1)").arg(Store.weightUnit(dialog.unitSystem))
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^(\d{1,3}([.,]\d{0,2})?)?$/ }
                text: dialog.prescription ? dialog.shown(dialog.prescription.weight_increment) : ""
            }
            TextField {
                id: percentageField
                visible: dialog.methods[dialog.methodIndex] === "percentage_based"
                width: parent.width
                label: qsTr("Percentage target (% 1RM)")
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^(\d{1,3}([.,]\d{0,2})?)?$/ }
                text: dialog.prescription ? dialog.text(dialog.prescription.percentage_target) : ""
            }
            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.prescription ? dialog.prescription.notes || "" : ""
            }
            KeyboardRoom {
                flickable: flickable
            }
        }

        VerticalScrollDecorator {}
    }
}
