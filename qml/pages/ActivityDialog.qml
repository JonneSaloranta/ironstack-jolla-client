import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Log a run, ride or any other non-gym activity, or correct one
// (`activity` set) - the web's activity form: date, an optional start time,
// duration in minutes, distance in km or mi, calories and notes. With
// `types` given the type can be picked. The page that opened it saves body().
Dialog {
    id: dialog

    property var type: null
    property var types: []
    property var activity: null

    readonly property string unitSystem: settings.unitSystem
    property date day: activity ? Store.parseDate(activity.date) : new Date()
    property bool hasTime: activity ? Store.present(activity.start_time) : false
    property int hour: activity && Store.present(activity.start_time)
                       ? parseInt(activity.start_time.split(":")[0], 10) : new Date().getHours()
    property int minute: activity && Store.present(activity.start_time)
                         ? parseInt(activity.start_time.split(":")[1], 10) : new Date().getMinutes()

    function pad(n) { return n < 10 ? "0" + n : String(n) }

    function body() {
        var distance = Store.distanceToMeters(distanceField.text, unitSystem)
        var calories = parseInt(caloriesField.text, 10)
        return {
            activity_type: type.id,
            date: Store.isoDate(day),
            start_time: hasTime ? pad(hour) + ":" + pad(minute) + ":00" : null,
            duration: Store.toDuration(parseInt(minutesField.text, 10) * 60),
            distance: isNaN(distance) ? null : distance,
            calories: isNaN(calories) ? null : calories,
            notes: notesArea.text
        }
    }

    canAccept: type !== null && parseInt(minutesField.text, 10) > 0

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.activity ? qsTr("Edit activity") : qsTr("Log activity")
            }

            ComboBox {
                visible: dialog.types.length > 0
                label: qsTr("Activity")
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

            DatePickerButton {
                label: qsTr("Date")
                date: dialog.day
                onPicked: dialog.day = date
            }

            TextSwitch {
                text: qsTr("Start time")
                checked: dialog.hasTime
                automaticCheck: false
                onClicked: dialog.hasTime = !dialog.hasTime
            }
            ValueButton {
                visible: dialog.hasTime
                label: qsTr("Start time")
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

            TextField {
                id: minutesField
                width: parent.width
                label: qsTr("Duration (minutes)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 99999 }
                text: dialog.activity ? String(Math.round(Store.parseDuration(dialog.activity.duration) / 60)) : ""
            }
            TextField {
                id: distanceField
                width: parent.width
                label: Store.isImperial(dialog.unitSystem) ? qsTr("Distance (mi)") : qsTr("Distance (km)")
                placeholderText: label
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: RegExpValidator { regExp: /^(\d{1,5}([.,]\d{0,2})?)?$/ }
                text: dialog.activity && Store.present(dialog.activity.distance)
                      ? Store.formatNumber(Store.metersToDistance(dialog.activity.distance, dialog.unitSystem)) : ""
            }
            TextField {
                id: caloriesField
                width: parent.width
                label: qsTr("Calories")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 0; top: 99999 }
                text: dialog.activity && Store.present(dialog.activity.calories) ? String(dialog.activity.calories) : ""
            }
            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.activity ? dialog.activity.notes || "" : ""
            }
            KeyboardRoom {
                flickable: flickable
            }
        }

        VerticalScrollDecorator {}
    }
}
