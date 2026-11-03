import QtQuick 2.0
import Sailfish.Silica 1.0

// A new workout in a program, or changes to one (`workout` set) - the
// web's workout form: name, the weekday it's scheduled for (none for a
// continuous program) and notes. The page that opened it saves body().
Dialog {
    id: dialog

    property var workout: null
    // 0 = Monday ... 6 = Sunday, -1 = none (Django's weekday numbering).
    property int weekday: workout && workout.scheduled_weekday !== null && workout.scheduled_weekday !== undefined
                          ? workout.scheduled_weekday : -1

    function weekdayName(index) {
        // Qt.locale().dayName counts from Sunday.
        return Qt.locale().dayName((index + 1) % 7, Locale.LongFormat)
    }

    function body() {
        return {
            name: nameField.text.trim(),
            scheduled_weekday: weekday >= 0 ? weekday : null,
            notes: notesArea.text
        }
    }

    canAccept: nameField.text.trim() !== ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.workout ? qsTr("Edit workout") : qsTr("New workout")
            }
            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Name")
                placeholderText: label
                text: dialog.workout ? dialog.workout.name : ""
            }
            ComboBox {
                label: qsTr("Weekday")
                value: dialog.weekday >= 0 ? dialog.weekdayName(dialog.weekday) : qsTr("None")
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("None")
                        onClicked: dialog.weekday = -1
                    }
                    Repeater {
                        model: 7
                        MenuItem {
                            text: dialog.weekdayName(index)
                            onClicked: dialog.weekday = index
                        }
                    }
                }
            }
            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.workout ? dialog.workout.notes || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
