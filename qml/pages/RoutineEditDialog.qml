import QtQuick 2.0
import Sailfish.Silica 1.0

// A stretch routine's name and description - the web's routine form. The
// page that opened it saves body().
Dialog {
    id: dialog

    property var routine: null

    function body() {
        return { name: nameField.text.trim(), description: descriptionArea.text }
    }

    canAccept: nameField.text.trim() !== ""

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: dialog.routine ? qsTr("Edit routine") : qsTr("New routine")
        }
        TextField {
            id: nameField
            width: parent.width
            label: qsTr("Name")
            placeholderText: label
            text: dialog.routine ? dialog.routine.name : ""
            focus: true
        }
        TextArea {
            id: descriptionArea
            width: parent.width
            label: qsTr("Description")
            placeholderText: label
            text: dialog.routine ? dialog.routine.description || "" : ""
        }
    }
}
