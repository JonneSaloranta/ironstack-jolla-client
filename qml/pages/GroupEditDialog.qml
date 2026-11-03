import QtQuick 2.0
import Sailfish.Silica 1.0

// A group's name and description - a new group, or an edit by its owner
// or an admin. The page that opened it saves body().
Dialog {
    id: dialog

    // The group as read, or null for a new one.
    property var group: null

    canAccept: nameField.text.trim() !== ""

    function body() {
        return { name: nameField.text.trim(), description: descriptionField.text.trim() }
    }

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: dialog.group ? qsTr("Edit group") : qsTr("New group")
        }
        TextField {
            id: nameField
            width: parent.width
            label: qsTr("Name")
            placeholderText: label
            text: dialog.group ? dialog.group.name : ""
            EnterKey.iconSource: "image://theme/icon-m-enter-next"
            EnterKey.onClicked: descriptionField.focus = true
        }
        TextArea {
            id: descriptionField
            width: parent.width
            label: qsTr("Description")
            placeholderText: label
            text: dialog.group ? dialog.group.description || "" : ""
        }
    }
}
