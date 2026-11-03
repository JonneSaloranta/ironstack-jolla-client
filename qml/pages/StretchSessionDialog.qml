import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/store.js" as Store

// Log stretching after the fact - the web's quick log: date, duration in
// minutes, optionally the routine, notes. With `session` set it corrects
// one; a logged session's routine can't change (the API refuses it).
// The page that opened it saves body().
Dialog {
    id: dialog

    property var session: null
    property var routines: []
    property var routine: null
    property int initialMinutes: 10
    property date day: session ? Store.parseDate(session.date) : new Date()

    function body() {
        var result = {
            date: Store.isoDate(day),
            duration: Store.toDuration(parseInt(minutesField.text, 10) * 60),
            notes: notesArea.text
        }
        if (!session)
            result.routine = routine ? routine.id : null
        return result
    }

    canAccept: parseInt(minutesField.text, 10) > 0

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.session ? qsTr("Edit session") : qsTr("Log stretching")
            }

            ComboBox {
                visible: !dialog.session && dialog.routines.length > 0
                label: qsTr("Routine")
                value: dialog.routine ? Store.contentName(dialog.routine.name) : qsTr("None")
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("None")
                        onClicked: dialog.routine = null
                    }
                    Repeater {
                        model: dialog.routines
                        MenuItem {
                            text: Store.contentName(modelData.name)
                            onClicked: dialog.routine = modelData
                        }
                    }
                }
            }
            DatePickerButton {
                label: qsTr("Date")
                date: dialog.day
                onPicked: dialog.day = date
            }
            TextField {
                id: minutesField
                width: parent.width
                label: qsTr("Duration (minutes)")
                placeholderText: label
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: 1; top: 9999 }
                text: dialog.session ? String(Math.max(1, Math.round(Store.parseDuration(dialog.session.duration) / 60)))
                                     : String(dialog.initialMinutes)
            }
            TextArea {
                id: notesArea
                width: parent.width
                label: qsTr("Notes")
                placeholderText: label
                text: dialog.session ? dialog.session.notes || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
