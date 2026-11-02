import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Log a body measurement reading, or correct one (`reading` set) - the
// web's reading form. The value is typed in the user's unit for the type
// (kg/lb, cm/in, %) and sent canonical. With `types` given the type can be
// picked; otherwise it's `type`. The page that opened it saves body().
Dialog {
    id: dialog

    property var type: null
    property var types: []
    property var reading: null

    readonly property string unitSystem: settings.unitSystem
    readonly property date initial: reading ? new Date(reading.recorded_at) : new Date()
    property date day: initial
    property int hour: initial.getHours()
    property int minute: initial.getMinutes()

    function recordedAt() {
        return new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute).toISOString()
    }

    function body() {
        return {
            measurement_type: type.id,
            value: Store.displayToMeasurement(valueField.text, type.unit_kind, unitSystem),
            recorded_at: recordedAt(),
            notes: notesArea.text
        }
    }

    canAccept: type !== null && valueField.text !== ""
               && !isNaN(Store.displayToMeasurement(valueField.text, type.unit_kind, unitSystem))

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.reading ? qsTr("Edit reading") : qsTr("Log reading")
            }

            ComboBox {
                visible: dialog.types.length > 0
                label: qsTr("Measurement")
                value: dialog.type ? Store.contentName(dialog.type.name) : ""
                menu: ContextMenu {
                    Repeater {
                        model: dialog.types
                        MenuItem {
                            text: Store.contentName(modelData.name)
                            onClicked: dialog.type = modelData
                        }
                    }
                }
            }

            TextField {
                id: valueField
                width: parent.width
                label: dialog.type ? Store.contentName(dialog.type.name) + " ("
                                     + Store.measurementUnit(dialog.type.unit_kind, dialog.unitSystem) + ")" : ""
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^\d{0,4}([.,]\d{0,2})?$/ }
                text: dialog.reading && dialog.type
                      ? Store.formatNumber(Store.measurementToDisplay(dialog.reading.value, dialog.type.unit_kind, dialog.unitSystem))
                      : ""
            }

            DatePickerButton {
                label: qsTr("Date")
                date: dialog.day
                onPicked: dialog.day = date
            }

            ValueButton {
                label: qsTr("Time")
                value: Format.formatDate(new Date(2000, 0, 1, dialog.hour, dialog.minute), Formatter.TimeValue)
                onClicked: {
                    var picker = pageStack.push("Sailfish.Silica.TimePickerDialog", {
                        hour: dialog.hour, minute: dialog.minute
                    })
                    picker.accepted.connect(function() {
                        dialog.hour = picker.hour
                        dialog.minute = picker.minute
                    })
                }
            }

            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.reading ? dialog.reading.notes || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
